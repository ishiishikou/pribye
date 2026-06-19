import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return SystemLanguageModel.default.isAvailable
    }
    #else
    if #available(iOS 26.0, *) {
      return true
    }
    #endif
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
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), availability.isSupported {
      return try await analyzeWithFoundationModels(pages: pages)
    }
    #endif
    return try await fallback.analyze(pages: pages)
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private func analyzeWithFoundationModels(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    let session = LanguageModelSession(
      model: .default,
      instructions: """
      あなたは学校・幼稚園などの配布プリントから、ユーザーが行動すべき最小限のタスクだけを抽出します。
      外部知識で補完せず、OCR入力に含まれる内容だけを使ってください。
      分類、場所、優先度、全文要約は作らないでください。
      日付は分かる場合だけ yyyy-MM-dd で返してください。
      根拠はOCR行の text をそのまま短く返し、対応する observation ID を必ず選んでください。
      """
    )

    let response = try await session.respond(
      to: makeFoundationModelPrompt(pages: pages),
      generating: FoundationModelAnalysisOutput.self,
      includeSchemaInPrompt: true
    )

    return try response.content.analysisResult()
  }

  private func makeFoundationModelPrompt(pages: [OCRPageSnapshot]) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: .now)
    let pageText = pages
      .map { page in
        let observations = page.observations
          .map { "- id: \($0.id.uuidString)\n  text: \($0.text)" }
          .joined(separator: "\n")
        return "Page \(page.pageIndex + 1):\n\(observations)"
      }
      .joined(separator: "\n\n")

    return """
    今日の日付: \(today)

    次のOCR行から、提出、持参、申込、準備、検温、支払い、参加など、ユーザーが行動すべきタスクだけを抽出してください。

    期間がある場合:
    - dueStart に開始日
    - dueEnd に終了日

    期限だけの場合:
    - dueEnd に期限日
    - dueStart は空

    日付が年なしの場合は、今日の日付を基準に最も自然な年を補ってください。
    行動ではない見出し、説明文、挨拶、問い合わせ先はタスクにしないでください。

    OCR:
    \(pageText)
    """
  }
  #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A minimal task extraction result from a printed school notice")
private struct FoundationModelAnalysisOutput {
  @Guide(description: "A short title for the printed document in Japanese")
  var documentTitle: String

  @Guide(description: "Only actionable tasks found in the OCR text")
  var tasks: [FoundationModelTaskOutput]

  func analysisResult() throws -> AnalysisResult {
    let convertedTasks = tasks.compactMap { task -> TaskDraft? in
      let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        return nil
      }

      return TaskDraft(
        title: title,
        note: task.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        dueStart: Self.parseDate(task.dueStart),
        dueEnd: Self.parseDate(task.dueEnd),
        evidenceText: task.evidenceText.trimmingCharacters(in: .whitespacesAndNewlines),
        evidenceObservationID: task.evidenceObservationID.flatMap(UUID.init(uuidString:))
      )
    }

    guard !convertedTasks.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    let title = documentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return AnalysisResult(
      documentTitle: title.isEmpty ? "プリント" : title,
      tasks: convertedTasks
    )
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }
}

@available(iOS 26.0, *)
@Generable(description: "One actionable task extracted from OCR text")
private struct FoundationModelTaskOutput {
  @Guide(description: "A concise task title in Japanese")
  var title: String

  @Guide(description: "A short optional note. Leave empty unless it is needed to act.")
  var note: String?

  @Guide(description: "Start date for a period task as yyyy-MM-dd. Leave empty when not applicable.")
  var dueStart: String?

  @Guide(description: "Deadline or end date as yyyy-MM-dd. Leave empty when not applicable.")
  var dueEnd: String?

  @Guide(description: "The exact OCR text that supports this task")
  var evidenceText: String

  @Guide(description: "The UUID string of the OCR observation that supports this task")
  var evidenceObservationID: String?
}
#endif

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
