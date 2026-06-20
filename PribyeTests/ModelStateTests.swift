import CoreGraphics
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
    XCTAssertEqual(document.status.userLabel, "AI解析中")

    document.status = .ready

    XCTAssertEqual(document.status.userLabel, "タスク化済み")
  }

  func testPageStoresCropCorners() {
    let page = PageRecord(pageIndex: 0)

    page.setCropCorners([
      CGPoint(x: 0.1, y: 0.2),
      CGPoint(x: 0.8, y: 0.2),
      CGPoint(x: 0.9, y: 0.7),
      CGPoint(x: 0.2, y: 0.9)
    ])

    XCTAssertEqual(page.cropTopLeftX, 0.1)
    XCTAssertEqual(page.cropTopLeftY, 0.2)
    XCTAssertEqual(page.cropTopRightX, 0.8)
    XCTAssertEqual(page.cropTopRightY, 0.2)
    XCTAssertEqual(page.cropBottomRightX, 0.9)
    XCTAssertEqual(page.cropBottomRightY, 0.7)
    XCTAssertEqual(page.cropBottomLeftX, 0.2)
    XCTAssertEqual(page.cropBottomLeftY, 0.9)
  }
}
