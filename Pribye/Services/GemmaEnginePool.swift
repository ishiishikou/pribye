import Foundation
#if canImport(LiteRTLM)
import LiteRTLM
#endif

enum GemmaEngineReleaseReason: Equatable, Sendable {
  case idleTimeout
  case memoryWarning
  case modelDeletion
  case backendFailure
  case cacheReplacement
}

struct GemmaEnginePoolSnapshot: Equatable, Sendable {
  var cachedBackend: GemmaInferenceBackend?
  var isEngineInUse: Bool
  var pendingReleaseReason: GemmaEngineReleaseReason?
}

protocol GemmaInferenceEngine: Sendable {
  func initialize() async throws
  func generate(prompt: String) async throws -> String
}

protocol GemmaInferenceEngineFactory: Sendable {
  func makeEngine(
    modelURL: URL,
    backend: GemmaInferenceBackend
  ) async throws -> any GemmaInferenceEngine
}

protocol GemmaEngineIdleSleeper: Sendable {
  func sleep(for duration: Duration) async
}

struct SystemGemmaEngineIdleSleeper: GemmaEngineIdleSleeper {
  func sleep(for duration: Duration) async {
    try? await Task.sleep(for: duration)
  }
}

actor GemmaEnginePool {
  static let defaultIdleTimeout: Duration = .seconds(5 * 60)
  static let shared = GemmaEnginePool(
    factory: DefaultGemmaInferenceEngineFactory()
  )

  private struct CacheKey: Equatable, Sendable {
    var modelPath: String
    var modelSHA256: String
    var backend: GemmaInferenceBackend
  }

  private struct CachedEngine: Sendable {
    var key: CacheKey
    var engine: any GemmaInferenceEngine
  }

  private let factory: any GemmaInferenceEngineFactory
  private let idleTimeout: Duration
  private let idleSleeper: any GemmaEngineIdleSleeper

  private var cachedEngine: CachedEngine?
  private var isEngineInUse = false
  private var engineUseWaiters: [CheckedContinuation<Void, Never>] = []
  private var pendingReleaseReason: GemmaEngineReleaseReason?
  private var idleReleaseTask: Task<Void, Never>?
  private var idleReleaseGeneration: UInt64 = 0

  init(
    factory: any GemmaInferenceEngineFactory,
    idleTimeout: Duration = GemmaEnginePool.defaultIdleTimeout,
    idleSleeper: any GemmaEngineIdleSleeper = SystemGemmaEngineIdleSleeper()
  ) {
    self.factory = factory
    self.idleTimeout = idleTimeout
    self.idleSleeper = idleSleeper
  }

  func generate(
    prompt: String,
    modelURL: URL,
    modelSHA256: String,
    backend: GemmaInferenceBackend
  ) async throws -> String {
    let key = CacheKey(
      modelPath: modelURL.standardizedFileURL.path,
      modelSHA256: modelSHA256,
      backend: backend
    )

    await acquireEngineUse()
    cancelIdleRelease()

    var shouldScheduleIdleRelease = false
    defer {
      finishEngineUse(shouldScheduleIdleRelease: shouldScheduleIdleRelease)
    }

    do {
      try Task.checkCancellation()
      let engine = try await cachedOrInitializedEngine(for: key, modelURL: modelURL)
      let content = try await engine.generate(prompt: prompt)
      shouldScheduleIdleRelease = true
      return content
    } catch is CancellationError {
      shouldScheduleIdleRelease = cachedEngine?.key == key
      throw CancellationError()
    } catch {
      discardCachedEngine(matching: key, reason: .backendFailure)
      throw error
    }
  }

  func releaseForMemoryWarning() {
    requestRelease(reason: .memoryWarning)
  }

  func releaseForModelDeletion(
    operation: @Sendable () async throws -> Void
  ) async rethrows {
    await acquireEngineUse()
    cancelIdleRelease()
    defer {
      pendingReleaseReason = nil
      releaseEngineUse()
    }

    if cachedEngine == nil {
      NSLog("%@", "Gemma Engine release before model deletion: no cached Engine.")
    } else {
      releaseCachedEngine(reason: .modelDeletion)
    }
    try await operation()
  }

  func snapshot() -> GemmaEnginePoolSnapshot {
    GemmaEnginePoolSnapshot(
      cachedBackend: cachedEngine?.key.backend,
      isEngineInUse: isEngineInUse,
      pendingReleaseReason: pendingReleaseReason
    )
  }

  private func cachedOrInitializedEngine(
    for key: CacheKey,
    modelURL: URL
  ) async throws -> any GemmaInferenceEngine {
    if let cachedEngine, cachedEngine.key == key {
      NSLog(
        "%@",
        "Gemma Engine reused: model=\(modelURL.lastPathComponent), backend=\(key.backend.rawValue)."
      )
      return cachedEngine.engine
    }

    if cachedEngine != nil {
      releaseCachedEngine(reason: .cacheReplacement)
    }

    NSLog(
      "%@",
      "Gemma Engine new initialization: model=\(modelURL.lastPathComponent), backend=\(key.backend.rawValue)."
    )

    do {
      let engine = try await factory.makeEngine(
        modelURL: modelURL,
        backend: key.backend
      )
      try await engine.initialize()
      cachedEngine = CachedEngine(key: key, engine: engine)
      return engine
    } catch {
      NSLog(
        "%@",
        "Gemma Engine initialization failed: backend=\(key.backend.rawValue)."
      )
      throw error
    }
  }

  private func acquireEngineUse() async {
    if !isEngineInUse {
      isEngineInUse = true
      return
    }

    await withCheckedContinuation { continuation in
      engineUseWaiters.append(continuation)
    }
  }

  private func finishEngineUse(shouldScheduleIdleRelease: Bool) {
    if let pendingReleaseReason {
      self.pendingReleaseReason = nil
      releaseCachedEngine(reason: pendingReleaseReason)
    } else if shouldScheduleIdleRelease,
              cachedEngine != nil,
              engineUseWaiters.isEmpty {
      scheduleIdleRelease()
    }

    releaseEngineUse()
  }

  private func releaseEngineUse() {
    guard !engineUseWaiters.isEmpty else {
      isEngineInUse = false
      return
    }

    let continuation = engineUseWaiters.removeFirst()
    continuation.resume()
  }

  private func requestRelease(reason: GemmaEngineReleaseReason) {
    cancelIdleRelease()

    guard isEngineInUse else {
      releaseCachedEngine(reason: reason)
      return
    }

    pendingReleaseReason = reason
    if reason == .memoryWarning {
      NSLog("%@", "Gemma Engine memory-warning release deferred until inference completes.")
    }
  }

  private func scheduleIdleRelease() {
    cancelIdleRelease()
    let generation = idleReleaseGeneration
    let idleTimeout = idleTimeout
    let idleSleeper = idleSleeper

    idleReleaseTask = Task { [weak self] in
      await idleSleeper.sleep(for: idleTimeout)
      await self?.releaseForIdleTimeout(generation: generation)
    }
  }

  private func cancelIdleRelease() {
    idleReleaseTask?.cancel()
    idleReleaseTask = nil
    idleReleaseGeneration &+= 1
  }

  private func releaseForIdleTimeout(generation: UInt64) {
    guard
      generation == idleReleaseGeneration,
      !isEngineInUse
    else {
      return
    }

    idleReleaseTask = nil
    releaseCachedEngine(reason: .idleTimeout)
  }

  private func discardCachedEngine(
    matching key: CacheKey,
    reason: GemmaEngineReleaseReason
  ) {
    guard cachedEngine?.key == key else {
      return
    }
    releaseCachedEngine(reason: reason)
  }

  private func releaseCachedEngine(reason: GemmaEngineReleaseReason) {
    guard let releasedEngine = cachedEngine else {
      return
    }
    cachedEngine = nil

    let backend = releasedEngine.key.backend.rawValue
    switch reason {
    case .idleTimeout:
      NSLog("%@", "Gemma Engine released after idle timeout: backend=\(backend).")
    case .memoryWarning:
      NSLog("%@", "Gemma Engine released for memory warning: backend=\(backend).")
    case .modelDeletion:
      NSLog("%@", "Gemma Engine released before model deletion: backend=\(backend).")
    case .backendFailure:
      NSLog("%@", "Gemma Engine discarded after backend failure: backend=\(backend).")
    case .cacheReplacement:
      NSLog("%@", "Gemma Engine released before backend or model switch: backend=\(backend).")
    }
  }
}

private struct DefaultGemmaInferenceEngineFactory: GemmaInferenceEngineFactory {
  func makeEngine(
    modelURL: URL,
    backend: GemmaInferenceBackend
  ) async throws -> any GemmaInferenceEngine {
    #if canImport(LiteRTLM)
    return try LiteRTGemmaInferenceEngine(
      modelURL: modelURL,
      backend: backend
    )
    #else
    throw DocumentAnalyzerError.modelLoadFailed
    #endif
  }
}

#if canImport(LiteRTLM)
private extension GemmaInferenceBackend {
  var liteRTBackend: Backend {
    switch self {
    case .gpu:
      return .gpu
    case .cpu:
      return .cpu()
    }
  }
}

private struct LiteRTGemmaInferenceEngine: GemmaInferenceEngine {
  private let engine: Engine

  init(
    modelURL: URL,
    backend: GemmaInferenceBackend
  ) throws {
    let config = try EngineConfig(
      modelPath: modelURL.path,
      backend: backend.liteRTBackend,
      maxNumTokens: 2048,
      cacheDir: NSTemporaryDirectory()
    )
    engine = Engine(engineConfig: config)
  }

  func initialize() async throws {
    try await engine.initialize()
  }

  func generate(prompt: String) async throws -> String {
    let conversation = try await engine.createConversation()
    let response = try await conversation.sendMessage(Message(prompt))
    let content = response.toString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      throw DocumentAnalyzerError.malformedModelOutput
    }
    return content
  }
}
#endif
