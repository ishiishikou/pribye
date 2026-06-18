import Foundation

struct ParsedDateRange: Equatable, Sendable {
  var start: Date?
  var end: Date?
}

struct DateRangeParser: Sendable {
  var calendar: Calendar = .current
  var referenceDate: Date = .now

  func parse(_ text: String) -> ParsedDateRange {
    if let range = parsePeriod(text) {
      return range
    }
    if let date = parseSingleDate(text) {
      return ParsedDateRange(start: date, end: nil)
    }
    return ParsedDateRange(start: nil, end: nil)
  }

  private func parsePeriod(_ text: String) -> ParsedDateRange? {
    let normalized = text
      .replacingOccurrences(of: "〜", with: "-")
      .replacingOccurrences(of: "～", with: "-")
      .replacingOccurrences(of: "から", with: "-")

    let pattern = #"(\d{1,2})\s*(?:月|/)\s*(\d{1,2})\s*(?:日)?\s*-\s*(?:(\d{1,2})\s*(?:月|/))?\s*(\d{1,2})"#
    guard let match = firstMatch(pattern: pattern, in: normalized) else {
      return nil
    }

    let startMonth = int(match[1])
    let startDay = int(match[2])
    let endMonth = int(match[3]) ?? startMonth
    let endDay = int(match[4])

    guard
      let startMonth,
      let startDay,
      let endMonth,
      let endDay,
      let start = makeDate(month: startMonth, day: startDay),
      let end = makeDate(month: endMonth, day: endDay)
    else {
      return nil
    }

    return ParsedDateRange(start: start, end: end)
  }

  private func parseSingleDate(_ text: String) -> Date? {
    let pattern = #"(\d{1,2})\s*(?:月|/)\s*(\d{1,2})\s*(?:日)?"#
    guard let match = firstMatch(pattern: pattern, in: text) else {
      return nil
    }
    guard let month = int(match[1]), let day = int(match[2]) else {
      return nil
    }
    return makeDate(month: month, day: day)
  }

  private func makeDate(month: Int, day: Int) -> Date? {
    let year = calendar.component(.year, from: referenceDate)
    var components = DateComponents()
    components.calendar = calendar
    components.year = year
    components.month = month
    components.day = day
    return calendar.date(from: components)
  }

  private func firstMatch(pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else {
      return nil
    }
    return (0..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard let swiftRange = Range(range, in: text) else {
        return ""
      }
      return String(text[swiftRange])
    }
  }

  private func int(_ value: String?) -> Int? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return Int(value)
  }
}
