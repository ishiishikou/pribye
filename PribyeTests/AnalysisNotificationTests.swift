import XCTest
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

    XCTAssertEqual(AnalysisNotificationTapInbox.shared.drain(), [notification])
    XCTAssertTrue(AnalysisNotificationTapInbox.shared.drain().isEmpty)
  }
}
