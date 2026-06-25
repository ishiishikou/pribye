import Foundation
import SwiftUI
import UserNotifications

extension Notification.Name {
  static let analysisNotificationTapped = Notification.Name("analysisNotificationTapped")
}

enum AnalysisNotificationOutcome: Equatable {
  case success
  case failure

  var message: String {
    switch self {
    case .success:
      return "解析が完了しました"
    case .failure:
      return "解析に失敗しました"
    }
  }
}

struct AnalysisCompletionNotification: Equatable, Identifiable {
  let id = UUID()
  var documentID: UUID
  var outcome: AnalysisNotificationOutcome

  var message: String {
    outcome.message
  }

  var destinationTab: AppTab {
    switch outcome {
    case .success:
      return .tasks
    case .failure:
      return .prints
    }
  }

  init(documentID: UUID, outcome: AnalysisNotificationOutcome) {
    self.documentID = documentID
    self.outcome = outcome
  }

  init?(userInfo: [AnyHashable: Any]) {
    guard
      let documentIDString = userInfo["documentID"] as? String,
      let documentID = UUID(uuidString: documentIDString),
      let outcomeString = userInfo["outcome"] as? String
    else {
      return nil
    }

    switch outcomeString {
    case "success":
      self.init(documentID: documentID, outcome: .success)
    case "failure":
      self.init(documentID: documentID, outcome: .failure)
    default:
      return nil
    }
  }
}

final class AnalysisNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  static let shared = AnalysisNotificationDelegate()

  private override init() {}

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard let notification = AnalysisCompletionNotification(
      userInfo: response.notification.request.content.userInfo
    ) else {
      return
    }

    await AnalysisNotificationTapInbox.shared.enqueue(notification)
  }
}

@MainActor
final class AnalysisNotificationTapInbox {
  static let shared = AnalysisNotificationTapInbox()

  private var pendingNotifications: [AnalysisCompletionNotification] = []

  private init() {}

  func enqueue(_ notification: AnalysisCompletionNotification) {
    pendingNotifications.append(notification)
    NotificationCenter.default.post(name: .analysisNotificationTapped, object: nil)
  }

  func drain() -> [AnalysisCompletionNotification] {
    let notifications = pendingNotifications
    pendingNotifications.removeAll()
    return notifications
  }
}

@MainActor
protocol AnalysisNotificationServiceProtocol {
  func requestAuthorizationIfNeeded() async
  func scheduleLocalCompletionNotification(_ notification: AnalysisCompletionNotification) async
}

struct AnalysisNotificationService: AnalysisNotificationServiceProtocol {
  private let center: UNUserNotificationCenter
  private let defaults: UserDefaults
  private let authorizationRequestedKey = "analysisNotificationAuthorizationRequested"

  init(
    center: UNUserNotificationCenter = .current(),
    defaults: UserDefaults = .standard
  ) {
    self.center = center
    self.defaults = defaults
  }

  func requestAuthorizationIfNeeded() async {
    guard !defaults.bool(forKey: authorizationRequestedKey) else {
      return
    }

    defaults.set(true, forKey: authorizationRequestedKey)
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  func scheduleLocalCompletionNotification(_ notification: AnalysisCompletionNotification) async {
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "プリバイ"
    content.body = notification.message
    content.sound = .default
    content.userInfo = [
      "documentID": notification.documentID.uuidString,
      "outcome": notification.outcome == .success ? "success" : "failure"
    ]

    let request = UNNotificationRequest(
      identifier: "analysis-\(notification.documentID.uuidString)-\(notification.outcome)",
      content: content,
      trigger: nil
    )
    try? await center.add(request)
  }
}

@MainActor
@Observable
final class AnalysisNotificationStore {
  var foregroundNotification: AnalysisCompletionNotification?
  private var scenePhase: ScenePhase = .active

  private let service: AnalysisNotificationServiceProtocol

  init(service: AnalysisNotificationServiceProtocol = AnalysisNotificationService()) {
    self.service = service
  }

  func requestAuthorizationIfNeeded() async {
    await service.requestAuthorizationIfNeeded()
  }

  func updateScenePhase(_ scenePhase: ScenePhase) {
    self.scenePhase = scenePhase
  }

  func deliver(_ notification: AnalysisCompletionNotification) async {
    if scenePhase == .active {
      foregroundNotification = notification
    } else {
      await service.scheduleLocalCompletionNotification(notification)
    }
  }

  func clear(_ notification: AnalysisCompletionNotification) {
    if foregroundNotification?.id == notification.id {
      foregroundNotification = nil
    }
  }
}
