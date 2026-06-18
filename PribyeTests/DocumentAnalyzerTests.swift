import XCTest
@testable import Pribye

final class DocumentAnalyzerTests: XCTestCase {
  func testHeuristicAnalyzerExtractsActionableTask() async throws {
    let analyzer = HeuristicDocumentAnalyzer(dateParser: parserFor2026())
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ\n6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]

    let result = try await analyzer.analyze(pages: pages)

    XCTAssertEqual(result.documentTitle, "体育授業のお知らせ")
    XCTAssertEqual(result.tasks.count, 1)
    XCTAssertTrue(result.tasks[0].title.contains("体操服を持参"))
    XCTAssertEqual(result.tasks[0].evidenceObservationID, observationID)
  }

  func testHeuristicAnalyzerFailsWhenNoTasksExist() async {
    let analyzer = HeuristicDocumentAnalyzer(dateParser: parserFor2026())
    let pages = [
      OCRPageSnapshot(pageIndex: 0, text: "給食だより\n今月の献立です。", observations: [])
    ]

    do {
      _ = try await analyzer.analyze(pages: pages)
      XCTFail("Expected noActionableTasks")
    } catch {
      XCTAssertEqual(error as? DocumentAnalyzerError, .noActionableTasks)
    }
  }

  private func parserFor2026() -> DateRangeParser {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    return DateRangeParser(calendar: calendar, referenceDate: reference)
  }
}
