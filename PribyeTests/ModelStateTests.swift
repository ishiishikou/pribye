import XCTest
@testable import Pribye

final class ModelStateTests: XCTestCase {
  func testTaskCompletionUpdatesLifecycleAndTimestamp() {
    let task = ExtractedTaskRecord(title: "体操服を持参")

    task.setCompleted(true)

    XCTAssertTrue(task.isCompleted)
    XCTAssertEqual(task.lifecycle, .completed)
    XCTAssertNotNil(task.completedAt)

    task.setCompleted(false)

    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(task.lifecycle, .active)
    XCTAssertNil(task.completedAt)
  }

  func testDocumentStatusSeparatesInternalAndUserLabels() {
    let document = DocumentRecord(status: .aiProcessing)

    XCTAssertEqual(document.status, .aiProcessing)
    XCTAssertEqual(document.status.userLabel, "解析中")

    document.status = .ready

    XCTAssertEqual(document.status.userLabel, "タスク化済み")
  }
}
