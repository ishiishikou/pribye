import Combine
import Foundation

enum GemmaModelDownloadPhase: Equatable, Sendable {
  case idle
  case downloading
  case verifying
  case failed(String)
}

struct GemmaModelDownloadState: Equatable, Sendable {
  var phase: GemmaModelDownloadPhase = .idle
  var bytesDownloaded: Int64 = 0
  var totalBytes: Int64 = GemmaModelStore.estimatedDownloadSizeBytes
  var bytesPerSecond: Double = 0
  var estimatedTimeRemaining: TimeInterval?
  var allowsCellularAccess = false

  var isActive: Bool {
    switch phase {
    case .downloading, .verifying:
      return true
    case .idle, .failed:
      return false
    }
  }

  var progress: Double? {
    guard totalBytes > 0 else {
      return nil
    }
    return min(max(Double(bytesDownloaded) / Double(totalBytes), 0), 1)
  }
}

private enum GemmaDownloadNetworkPolicy: Hashable, Sendable {
  case wifiOnly
  case cellularAllowed

  var sessionIdentifier: String {
    switch self {
    case .wifiOnly:
      return "com.pribye.gemma-model-download.wifi"
    case .cellularAllowed:
      return "com.pribye.gemma-model-download.cellular"
    }
  }

  var allowsCellularAccess: Bool {
    self == .cellularAllowed
  }
}

fileprivate struct GemmaDownloadTaskKey: Hashable, Sendable {
  let sessionIdentifier: String
  let taskIdentifier: Int
}

private struct GemmaDownloadTaskSnapshot: Sendable {
  let key: GemmaDownloadTaskKey
  let bytesDownloaded: Int64
  let totalBytes: Int64
  let allowsCellularAccess: Bool
}

@MainActor
final class GemmaModelDownloadManager: ObservableObject {
  static let shared = GemmaModelDownloadManager()

  @Published private(set) var modelStatus: GemmaModelStatus
  @Published private(set) var state = GemmaModelDownloadState()
  @Published private(set) var statusMessage: String?

  private let delegate: GemmaModelBackgroundSessionDelegate
  private var activeTaskKeys: Set<GemmaDownloadTaskKey> = []
  private var verificationTask: Task<Void, Never>?
  private var verificationToken: UUID?
  private var backgroundCompletionHandlers: [String: () -> Void] = [:]
  private var backgroundSessionsReadyToComplete: Set<String> = []
  private var pendingSessionRestorations = 0
  private var ignoreDownloadCompletions = false
  private var lastProgressDate: Date?
  private var lastProgressBytes: Int64 = 0
  private var smoothedBytesPerSecond: Double = 0

  private lazy var wifiOnlySession = makeSession(policy: .wifiOnly)
  private lazy var cellularAllowedSession = makeSession(policy: .cellularAllowed)

  private var allSessions: [URLSession] {
    [wifiOnlySession, cellularAllowedSession]
  }

  private init() {
    modelStatus = GemmaModelStore.shared.status()
    delegate = GemmaModelBackgroundSessionDelegate()
    delegate.owner = self

    _ = allSessions
    restoreBackgroundTasks()
  }

  func startDownload(allowsCellularAccess: Bool) {
    guard !state.isActive, activeTaskKeys.isEmpty else {
      return
    }

    ignoreDownloadCompletions = false

    guard let downloadURL = URL(string: GemmaModelStore.modelDownloadURLString) else {
      state.phase = .failed("ダウンロードURLが不正です。")
      return
    }

    do {
      try GemmaModelStore.shared.prepareForDownload()
    } catch {
      state.phase = .failed("モデル保存領域を準備できませんでした。")
      return
    }

    let policy: GemmaDownloadNetworkPolicy = allowsCellularAccess ? .cellularAllowed : .wifiOnly
    let session = session(for: policy)
    var request = URLRequest(
      url: downloadURL,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 7 * 24 * 60 * 60
    )
    request.allowsConstrainedNetworkAccess = allowsCellularAccess
    request.allowsExpensiveNetworkAccess = allowsCellularAccess

    let task = session.downloadTask(with: request)
    task.taskDescription = "gemma-model"

    let key = GemmaDownloadTaskKey(
      sessionIdentifier: policy.sessionIdentifier,
      taskIdentifier: task.taskIdentifier
    )
    activeTaskKeys.insert(key)

    resetSpeedTracking(bytesDownloaded: 0)
    state = GemmaModelDownloadState(
      phase: .downloading,
      bytesDownloaded: 0,
      totalBytes: GemmaModelStore.estimatedDownloadSizeBytes,
      bytesPerSecond: 0,
      estimatedTimeRemaining: nil,
      allowsCellularAccess: allowsCellularAccess
    )
    statusMessage = nil
    task.resume()
  }

  func cancelDownload(showMessage: Bool = true) {
    verificationTask?.cancel()
    verificationTask = nil
    verificationToken = nil
    ignoreDownloadCompletions = true
    activeTaskKeys.removeAll()

    for session in allSessions {
      session.getAllTasks { tasks in
        tasks.forEach { $0.cancel() }
      }
    }

    try? GemmaModelStore.shared.deleteStagedDownload()
    state = GemmaModelDownloadState()
    if showMessage {
      statusMessage = "モデルのダウンロードを中止しました。"
    }
    attemptBackgroundEventCompletion()
  }

  func deleteModelAndDownloadData() {
    cancelDownload(showMessage: false)

    do {
      try GemmaModelStore.shared.deleteModel()
      modelStatus = .notDownloaded
      statusMessage = "モデルとダウンロード途中のデータを削除しました。"
    } catch {
      modelStatus = GemmaModelStore.shared.status()
      statusMessage = "モデルを削除できませんでした。"
    }
  }

  func refreshModelStatus() {
    modelStatus = GemmaModelStore.shared.status()
    if modelStatus == .invalid,
       GemmaModelStore.shared.hasModelFile,
       !state.isActive,
       pendingSessionRestorations == 0 {
      validateExistingModel()
    }
  }

  func setBackgroundCompletionHandler(
    _ completionHandler: @escaping () -> Void,
    for sessionIdentifier: String
  ) {
    backgroundCompletionHandlers[sessionIdentifier] = completionHandler
    attemptBackgroundEventCompletion()
  }

  fileprivate func handleProgress(
    key: GemmaDownloadTaskKey,
    bytesDownloaded: Int64,
    totalBytes: Int64
  ) {
    guard !ignoreDownloadCompletions else {
      return
    }
    activeTaskKeys.insert(key)

    let expectedBytes = totalBytes > 0 ? totalBytes : GemmaModelStore.estimatedDownloadSizeBytes
    let now = Date()

    if let lastProgressDate {
      let elapsed = now.timeIntervalSince(lastProgressDate)
      let transferred = bytesDownloaded - lastProgressBytes
      if elapsed > 0.25, transferred >= 0 {
        let currentSpeed = Double(transferred) / elapsed
        smoothedBytesPerSecond = smoothedBytesPerSecond == 0
          ? currentSpeed
          : (smoothedBytesPerSecond * 0.75) + (currentSpeed * 0.25)
      }
    }

    lastProgressDate = now
    lastProgressBytes = bytesDownloaded

    let remainingBytes = max(expectedBytes - bytesDownloaded, 0)
    let estimatedTimeRemaining = smoothedBytesPerSecond > 0
      ? Double(remainingBytes) / smoothedBytesPerSecond
      : nil

    state = GemmaModelDownloadState(
      phase: .downloading,
      bytesDownloaded: bytesDownloaded,
      totalBytes: expectedBytes,
      bytesPerSecond: smoothedBytesPerSecond,
      estimatedTimeRemaining: estimatedTimeRemaining,
      allowsCellularAccess: key.sessionIdentifier == GemmaDownloadNetworkPolicy.cellularAllowed.sessionIdentifier
    )
  }

  fileprivate func handleStagedDownload(
    key: GemmaDownloadTaskKey,
    stagedURL: URL
  ) {
    guard !ignoreDownloadCompletions else {
      try? FileManager.default.removeItem(at: stagedURL)
      return
    }

    activeTaskKeys.remove(key)

    state.phase = .verifying
    state.estimatedTimeRemaining = nil
    statusMessage = "ダウンロードしたモデルを検証しています。"

    verificationTask?.cancel()
    let token = UUID()
    verificationToken = token
    verificationTask = Task.detached(priority: .utility) { [weak self] in
      do {
        try GemmaModelStore.shared.validateStagedModelAndInstall()
        await self?.handleVerificationSucceeded(token: token)
      } catch is CancellationError {
        await self?.handleVerificationCancelled(token: token)
      } catch {
        await self?.handleVerificationFailed(token: token)
      }
    }
  }

  fileprivate func handleDownloadStagingFailure(
    key: GemmaDownloadTaskKey,
    message: String
  ) {
    guard !ignoreDownloadCompletions else {
      return
    }
    activeTaskKeys.remove(key)
    modelStatus = GemmaModelStore.shared.status()
    state.phase = .failed(message)
    statusMessage = message
  }

  fileprivate func handleTaskCompletion(
    key: GemmaDownloadTaskKey,
    errorCode: Int?,
    errorDescription: String?
  ) {
    guard let errorCode else {
      return
    }

    let wasActive = activeTaskKeys.remove(key) != nil
    guard wasActive else {
      return
    }

    if errorCode == NSURLErrorCancelled {
      if activeTaskKeys.isEmpty, case .downloading = state.phase {
        state = GemmaModelDownloadState()
      }
      return
    }

    let message = errorDescription.map { "モデルのダウンロードに失敗しました。\n\($0)" }
      ?? "モデルのダウンロードに失敗しました。"
    state.phase = .failed(message)
    statusMessage = message
  }

  fileprivate func finishBackgroundEvents(for sessionIdentifier: String) {
    guard backgroundCompletionHandlers[sessionIdentifier] != nil else {
      return
    }
    backgroundSessionsReadyToComplete.insert(sessionIdentifier)
    attemptBackgroundEventCompletion()
  }

  private func makeSession(policy: GemmaDownloadNetworkPolicy) -> URLSession {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: policy.sessionIdentifier
    )
    configuration.allowsCellularAccess = policy.allowsCellularAccess
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 7 * 24 * 60 * 60
    configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  private func session(for policy: GemmaDownloadNetworkPolicy) -> URLSession {
    switch policy {
    case .wifiOnly:
      return wifiOnlySession
    case .cellularAllowed:
      return cellularAllowedSession
    }
  }

  private func restoreBackgroundTasks() {
    pendingSessionRestorations = allSessions.count

    for session in allSessions {
      let sessionIdentifier = session.configuration.identifier ?? ""
      let allowsCellularAccess = sessionIdentifier == GemmaDownloadNetworkPolicy.cellularAllowed.sessionIdentifier

      session.getAllTasks { [weak self] tasks in
        let snapshots = tasks.map { task in
          GemmaDownloadTaskSnapshot(
            key: GemmaDownloadTaskKey(
              sessionIdentifier: sessionIdentifier,
              taskIdentifier: task.taskIdentifier
            ),
            bytesDownloaded: task.countOfBytesReceived,
            totalBytes: task.countOfBytesExpectedToReceive,
            allowsCellularAccess: allowsCellularAccess
          )
        }

        Task { @MainActor [weak self] in
          self?.restore(snapshots: snapshots)
          self?.completeSessionRestoration()
        }
      }
    }
  }

  private func restore(snapshots: [GemmaDownloadTaskSnapshot]) {
    guard let snapshot = snapshots.max(by: { $0.bytesDownloaded < $1.bytesDownloaded }) else {
      return
    }

    snapshots.forEach { activeTaskKeys.insert($0.key) }
    let expectedBytes = snapshot.totalBytes > 0
      ? snapshot.totalBytes
      : GemmaModelStore.estimatedDownloadSizeBytes

    resetSpeedTracking(bytesDownloaded: snapshot.bytesDownloaded)
    state = GemmaModelDownloadState(
      phase: .downloading,
      bytesDownloaded: snapshot.bytesDownloaded,
      totalBytes: expectedBytes,
      bytesPerSecond: 0,
      estimatedTimeRemaining: nil,
      allowsCellularAccess: snapshot.allowsCellularAccess
    )
    statusMessage = "バックグラウンドでモデルのダウンロードを継続しています。"
  }

  private func completeSessionRestoration() {
    pendingSessionRestorations = max(pendingSessionRestorations - 1, 0)
    guard pendingSessionRestorations == 0, activeTaskKeys.isEmpty else {
      return
    }

    if modelStatus == .invalid, GemmaModelStore.shared.hasModelFile {
      validateExistingModel()
    }
  }

  private func validateExistingModel() {
    guard verificationTask == nil else {
      return
    }

    state.phase = .verifying
    statusMessage = "保存済みモデルを検証しています。"

    let token = UUID()
    verificationToken = token
    verificationTask = Task.detached(priority: .utility) { [weak self] in
      do {
        try GemmaModelStore.shared.validateExistingModel()
        await self?.handleVerificationSucceeded(token: token)
      } catch is CancellationError {
        await self?.handleVerificationCancelled(token: token)
      } catch {
        await self?.handleVerificationFailed(token: token)
      }
    }
  }

  private func handleVerificationSucceeded(token: UUID) {
    guard verificationToken == token else {
      return
    }
    verificationTask = nil
    verificationToken = nil
    modelStatus = .ready
    state = GemmaModelDownloadState()
    statusMessage = "モデルの準備が完了しました。"
    attemptBackgroundEventCompletion()
  }

  private func handleVerificationCancelled(token: UUID) {
    guard verificationToken == token else {
      return
    }
    verificationTask = nil
    verificationToken = nil
    if case .verifying = state.phase {
      state = GemmaModelDownloadState()
    }
    attemptBackgroundEventCompletion()
  }

  private func handleVerificationFailed(token: UUID) {
    guard verificationToken == token else {
      return
    }
    verificationTask = nil
    verificationToken = nil
    try? GemmaModelStore.shared.deleteStagedDownload()
    modelStatus = GemmaModelStore.shared.status()
    let message = "モデルの検証に失敗しました。再ダウンロードしてください。"
    state.phase = .failed(message)
    statusMessage = message
    attemptBackgroundEventCompletion()
  }

  private func attemptBackgroundEventCompletion() {
    guard verificationTask == nil,
          !FileManager.default.fileExists(atPath: GemmaModelStore.shared.stagedDownloadURL.path)
    else {
      return
    }

    let identifiers = backgroundSessionsReadyToComplete
    for identifier in identifiers {
      guard let completionHandler = backgroundCompletionHandlers.removeValue(forKey: identifier) else {
        continue
      }
      backgroundSessionsReadyToComplete.remove(identifier)
      completionHandler()
    }
  }

  private func resetSpeedTracking(bytesDownloaded: Int64) {
    lastProgressDate = Date()
    lastProgressBytes = bytesDownloaded
    smoothedBytesPerSecond = 0
  }
}

private final class GemmaModelBackgroundSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
  weak var owner: GemmaModelDownloadManager?

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let key = taskKey(session: session, taskIdentifier: downloadTask.taskIdentifier)
    Task { @MainActor [weak owner] in
      owner?.handleProgress(
        key: key,
        bytesDownloaded: totalBytesWritten,
        totalBytes: totalBytesExpectedToWrite
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let key = taskKey(session: session, taskIdentifier: downloadTask.taskIdentifier)

    do {
      let stagedURL = try GemmaModelStore.shared.stageDownloadedFile(from: location)
      Task { @MainActor [weak owner] in
        owner?.handleStagedDownload(key: key, stagedURL: stagedURL)
      }
    } catch {
      Task { @MainActor [weak owner] in
        owner?.handleDownloadStagingFailure(
          key: key,
          message: "ダウンロードしたモデルを保存できませんでした。"
        )
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let key = taskKey(session: session, taskIdentifier: task.taskIdentifier)
    let nsError = error as NSError?
    let errorCode = nsError?.code
    let errorDescription = nsError?.localizedDescription
    Task { @MainActor [weak owner] in
      owner?.handleTaskCompletion(
        key: key,
        errorCode: errorCode,
        errorDescription: errorDescription
      )
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let sessionIdentifier = session.configuration.identifier else {
      return
    }
    Task { @MainActor [weak owner] in
      owner?.finishBackgroundEvents(for: sessionIdentifier)
    }
  }

  private func taskKey(session: URLSession, taskIdentifier: Int) -> GemmaDownloadTaskKey {
    GemmaDownloadTaskKey(
      sessionIdentifier: session.configuration.identifier ?? "",
      taskIdentifier: taskIdentifier
    )
  }
}
