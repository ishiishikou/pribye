import XCTest
@testable import Pribye

final class DateRangeParserTests: XCTestCase {
  func testParsesSingleJapaneseDeadline() {
    let parser = parserFor2026()

    let result = parser.parse("6月20日（金）までに体操服を持参してください。")

    XCTAssertEqual(component(.month, result.start), 6)
    XCTAssertEqual(component(.day, result.start), 20)
    XCTAssertNil(result.end)
  }

  func testParsesPeriodWithoutRepeatedMonth() {
    let parser = parserFor2026()

    let result = parser.parse("6/15〜6/20 毎朝検温")

    XCTAssertEqual(component(.month, result.start), 6)
    XCTAssertEqual(component(.day, result.start), 15)
    XCTAssertEqual(component(.month, result.end), 6)
    XCTAssertEqual(component(.day, result.end), 20)
  }

  private func parserFor2026() -> DateRangeParser {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    return DateRangeParser(calendar: calendar, referenceDate: reference)
  }

  private func component(_ component: Calendar.Component, _ date: Date?) -> Int? {
    guard let date else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.component(component, from: date)
  }
}
