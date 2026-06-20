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
    #endif
    return false
  }
}

struct FoundationModelsDocumentAnalyzer: DocumentAnalyzer {
  private let availability: AppleIntelligenceAvailability

  init(availability: AppleIntelligenceAvailability = AppleIntelligenceAvailability()) {
    self.availability = availability
  }

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), availability.isSupported {
      return try await analyzeWithFoundationModels(pages: pages)
    }
    #endif
    throw DocumentAnalyzerError.unsupportedDevice
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private func analyzeWithFoundationModels(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    let session = LanguageModelSession(
      model: .default,
      instructions: """
      あなたは学校・幼稚園などの配布プリントから、タスク管理アプリに登録するためのタスク一覧を作成するアシスタントです。
      OCRで読み取った内容のみを根拠として、ユーザーが実際に行うタスクを抽出してください。
      外部知識で内容を補完・推測してはいけません。
      OCRの誤認識と思われる箇所は、OCR内の文脈から自然に補正できる場合のみ補正してください。不確かな場合は補正しないでください。
      複数ページが渡された場合、タスク抽出対象は入力内で最初に表示されたPageのみとし、後続Pageは文脈理解のためだけに参照してください。
      分類、場所、優先度、全文要約は作成しないでください。
      ユーザーが一度の作業として実施できる内容を1タスクとし、同じ目的の連続した作業は1つにまとめてください。
      細かな手順には分割せず、必要以上にタスク数を増やさないでください。
      各タスクは15文字以内で簡潔に表現し、「〜してください」などの依頼表現は含めないでください。
      時系列は維持してください。
      日付はOCRから判断できる場合のみ yyyy-MM-dd 形式で返してください。不明な場合は設定しないでください。
      根拠には、対応するOCR行の text を短くそのまま引用し、対応する observation ID を必ず指定してください。
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
    let pageText = pages
      .map { page in
        let observations = page.observations
          .map { "- id: \($0.id.uuidString)\n  text: \($0.text)" }
          .joined(separator: "\n")
        return "Page \(page.pageIndex + 1):\n\(observations)"
      }
      .joined(separator: "\n\n")

    return """
    次のOCR行から、ユーザーが実際に行うタスクだけを抽出してください。
    行動ではない見出し、説明文、挨拶、問い合わせ先はタスクにしないでください。
    OCRに年まで判断できる情報がない日付は設定しないでください。

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
      let title = Self.compactTaskTitle(task.title)
      guard !title.isEmpty else {
        return nil
      }

      return TaskDraft(
        title: title,
        note: "",
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

  private static func compactTaskTitle(_ value: String) -> String {
    let title = value
      .replacingOccurrences(of: "してください", with: "")
      .replacingOccurrences(of: "お願いします", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return String(title.prefix(15))
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

    let compacted = title
      .replacingOccurrences(of: "してください", with: "")
      .replacingOccurrences(of: "します", with: "")
      .replacingOccurrences(of: #"^\s*に"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return String(compacted.prefix(15))
  }
}
