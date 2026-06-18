import Foundation

struct OCRPageSnapshot: Equatable, Sendable {
  var pageIndex: Int
  var text: String
  var observations: [OCRObservationSnapshot]
}

struct OCRObservationSnapshot: Equatable, Sendable {
  var id: UUID
  var text: String
}

struct TaskDraft: Equatable, Sendable {
  var title: String
  var note: String
  var dueStart: Date?
  var dueEnd: Date?
  var evidenceText: String
  var evidenceObservationID: UUID?
}

struct AnalysisResult: Equatable, Sendable {
  var documentTitle: String
  var tasks: [TaskDraft]
}

enum DocumentAnalyzerError: Error, Equatable {
  case noActionableTasks
  case unsupportedDevice
  case malformedModelOutput
}

protocol DocumentAnalyzer: Sendable {
  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult
}

struct AppleIntelligenceAvailability: Sendable {
  var isSupported: Bool {
    if #available(iOS 26.0, *) {
      return true
    }
    return false
  }
}

struct FoundationModelsDocumentAnalyzer: DocumentAnalyzer {
  private let availability: AppleIntelligenceAvailability
  private let fallback: HeuristicDocumentAnalyzer

  init(
    availability: AppleIntelligenceAvailability = AppleIntelligenceAvailability(),
    fallback: HeuristicDocumentAnalyzer = HeuristicDocumentAnalyzer()
  ) {
    self.availability = availability
    self.fallback = fallback
  }

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    guard availability.isSupported else {
      throw DocumentAnalyzerError.unsupportedDevice
    }

    // Foundation Models API calls belong here. The heuristic parser keeps the
    // app usable in CI and until Apple Intelligence is validated on-device.
    return try await fallback.analyze(pages: pages)
  }
}

struct HeuristicDocumentAnalyzer: DocumentAnalyzer {
  var dateParser: DateRangeParser = DateRangeParser()

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    let lines = pages
      .flatMap { page in page.text.components(separatedBy: .newlines) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard !lines.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    let title = inferTitle(from: lines)
    let tasks = lines.compactMap { line -> TaskDraft? in
      let range = dateParser.parse(line)
      guard range.start != nil || range.end != nil || containsActionCue(line) else {
        return nil
      }

      let title = cleanupTaskTitle(line)
      guard !title.isEmpty else {
        return nil
      }

      let evidenceObservationID = pages
        .flatMap(\.observations)
        .first { line.contains($0.text) || $0.text.contains(line) }?
        .id

      return TaskDraft(
        title: title,
        note: "",
        dueStart: range.start,
        dueEnd: range.end,
        evidenceText: line,
        evidenceObservationID: evidenceObservationID
      )
    }

    guard !tasks.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    return AnalysisResult(documentTitle: title, tasks: tasks)
  }

  private func inferTitle(from lines: [String]) -> String {
    lines.first { line in
      line.count >= 4 && line.count <= 30 && !containsActionCue(line)
    } ?? "プリント"
  }

  private func containsActionCue(_ line: String) -> Bool {
    let cues = ["持参", "提出", "申込", "申し込み", "検温", "持って", "用意", "まで", "締切", "期限"]
    return cues.contains { line.contains($0) }
  }

  private func cleanupTaskTitle(_ line: String) -> String {
    var title = line
    let removablePatterns = [
      #"\d{1,2}\s*(?:月|/)\s*\d{1,2}\s*(?:日)?(?:\s*[（(].*?[）)])?\s*まで"#,
      #"\d{1,2}\s*(?:月|/)\s*\d{1,2}\s*(?:日)?\s*[〜～\-]\s*(?:\d{1,2}\s*(?:月|/))?\s*\d{1,2}\s*(?:日)?"#
    ]

    for pattern in removablePatterns {
      title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    return title
      .replacingOccurrences(of: "してください", with: "")
      .replacingOccurrences(of: "します", with: "")
      .replacingOccurrences(of: #"^\s*に"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }
}
