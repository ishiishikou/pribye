import XCTest
import SwiftUI
@testable import Pribye

final class AnalysisNotificationTests: XCTestCase {
  func testCompletionNotificationUsesAbstractMessages() {
    let documentID = UUID()

    XCTAssertEqual(
      AnalysisCompletionNotification(documentID: documentID, outcome: .success).message,
      "解析が完了しました"
    )
    XCTAssertEqual(
      AnalysisCompletionNotification(documentID: documentID, outcome: .failure).message,
      "解析に失敗しました"
    )
  }

  func testCompletionNotificationRoutesByOutcome() {
    let documentID = UUID()

    XCTAssertEqual(
      AnalysisCompletionNotification(documentID: documentID, outcome: .success).destinationTab,
      .tasks
    )
    XCTAssertEqual(
      AnalysisCompletionNotification(documentID: documentID, outcome: .failure).destinationTab,
      .prints
    )
  }

  func testCompletionNotificationParsesUserInfo() {
    let documentID = UUID()

    let notification = AnalysisCompletionNotification(userInfo: [
      "documentID": documentID.uuidString,
      "outcome": "failure"
    ])

    XCTAssertEqual(notification?.documentID, documentID)
    XCTAssertEqual(notification?.outcome, .failure)
  }

  func testCompletionNotificationRejectsInvalidUserInfo() {
    XCTAssertNil(AnalysisCompletionNotification(userInfo: [
      "documentID": UUID().uuidString,
      "outcome": "unknown"
    ]))
  }

  @MainActor
  func testTapInboxBuffersNotificationUntilDrained() {
    _ = AnalysisNotificationTapInbox.shared.drain()
    let notification = AnalysisCompletionNotification(documentID: UUID(), outcome: .success)

    AnalysisNotificationTapInbox.shared.enqueue(notification)

    let drainedNotifications = AnalysisNotificationTapInbox.shared.drain()
    let remainingNotifications = AnalysisNotificationTapInbox.shared.drain()
    XCTAssertEqual(drainedNotifications, [notification])
    XCTAssertTrue(remainingNotifications.isEmpty)
  }

  @MainActor
  func testStoreDeliversForegroundNotificationWhenSceneIsActive() async {
    let service = RecordingAnalysisNotificationService()
    let store = AnalysisNotificationStore(service: service)
    let notification = AnalysisCompletionNotification(documentID: UUID(), outcome: .success)

    await store.deliver(notification)

    let foregroundNotification = store.foregroundNotification
    let scheduledNotifications = service.scheduledNotifications
    XCTAssertEqual(foregroundNotification, notification)
    XCTAssertTrue(scheduledNotifications.isEmpty)
  }

  @MainActor
  func testStoreSchedulesLocalNotificationWhenSceneIsInBackground() async {
    let service = RecordingAnalysisNotificationService()
    let store = AnalysisNotificationStore(service: service)
    let notification = AnalysisCompletionNotification(documentID: UUID(), outcome: .failure)

    store.updateScenePhase(.background)
    await store.deliver(notification)

    let foregroundNotification = store.foregroundNotification
    let scheduledNotifications = service.scheduledNotifications
    XCTAssertNil(foregroundNotification)
    XCTAssertEqual(scheduledNotifications, [notification])
  }
}

@MainActor
private final class RecordingAnalysisNotificationService: AnalysisNotificationServiceProtocol {
  private(set) var scheduledNotifications: [AnalysisCompletionNotification] = []

  func requestAuthorizationIfNeeded() async {}

  func scheduleLocalCompletionNotification(_ notification: AnalysisCompletionNotification) async {
    scheduledNotifications.append(notification)
  }
}
