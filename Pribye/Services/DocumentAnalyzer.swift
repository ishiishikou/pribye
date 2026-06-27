import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(LiteRTLM)
import LiteRTLM
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
  case modelNotReady
  case modelLoadFailed
  case malformedModelOutput
}

protocol DocumentAnalyzer: Sendable {
  var shouldDeduplicateTasks: Bool { get }
  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult
}

extension DocumentAnalyzer {
  var shouldDeduplicateTasks: Bool { true }
}

protocol GemmaTextGenerating: Sendable {
  func generate(prompt: String) async throws -> String
}

struct GemmaDocumentAnalyzer: DocumentAnalyzer {
  var shouldDeduplicateTasks: Bool { false }

  private let modelStore: GemmaModelStore
  private let textGenerator: GemmaTextGenerating?

  init(
    modelStore: GemmaModelStore = .shared,
    textGenerator: GemmaTextGenerating? = nil
  ) {
    self.modelStore = modelStore
    self.textGenerator = textGenerator
  }

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    guard !Self.plainOCRText(from: pages).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    let generator: GemmaTextGenerating
    if let textGenerator {
      generator = textGenerator
    } else {
      guard modelStore.status() == .ready else {
        throw DocumentAnalyzerError.modelNotReady
      }
      generator = try Self.defaultTextGenerator(modelURL: modelStore.modelFileURL)
    }

    let response = try await generator.generate(prompt: Self.prompt(for: pages))
    return try Self.analysisResult(from: response, pages: pages)
  }

  private static func defaultTextGenerator(modelURL: URL) throws -> GemmaTextGenerating {
    #if canImport(LiteRTLM)
    return LiteRTGemmaTextGenerator(modelURL: modelURL)
    #else
    throw DocumentAnalyzerError.modelLoadFailed
    #endif
  }

  static func plainOCRText(from pages: [OCRPageSnapshot]) -> String {
    FoundationModelsDocumentAnalyzer.plainOCRText(from: pages)
  }

  static func prompt(for pages: [OCRPageSnapshot]) -> String {
    let sortedPages = pages.sorted { $0.pageIndex < $1.pageIndex }
    let pageBlocks = sortedPages.enumerated().map { index, page in
      let observations = page.observations.map {
        "- id: \($0.id.uuidString)\n  text: \($0.text)"
      }.joined(separator: "\n")
      let label = index == 0 ? "TARGET_PAGE" : "CONTEXT"
      return """
      \(label) pageIndex=\(page.pageIndex)
      \(observations.isEmpty ? page.text : observations)
      """
    }.joined(separator: "\n\n")

    return """
    OCRで読み取れた内容だけを根拠に、保護者がTODOアプリへ登録して実行する行動だけを抽出してください。
    外部知識で補完しないでください。OCR誤認識は文脈から明らかな場合だけ補正してください。
    園や学校が行う活動、説明、理由、注意事項だけの文章は抽出しないでください。
    CONTEXTはTARGET_PAGE末尾の文脈補助だけに使い、CONTEXTだけから新しいタスクを抽出しないでください。
    同じ目的の作業は1つにまとめ、タイトルは15文字以内にしてください。「してください」はタイトルに含めないでください。
    時系列を維持し、最終確認として「これは保護者がTODOアプリに登録して実行する行動か？」がYESのものだけを残してください。
    日付がOCRから明確な場合だけdateをyyyy-MM-ddで出力し、不明ならnullにしてください。
    evidenceObservationIDには根拠に対応するOCR idを入れてください。
    出力は次のJSONのみです。説明文やMarkdownは出力しないでください。
    {"documentTitle":"20文字以内のタイトル","tasks":[{"title":"15文字以内","note":"タスク本文","date":"yyyy-MM-ddまたはnull","evidenceText":"根拠OCRの短い引用","evidenceObservationID":"UUID"}]}

    \(pageBlocks)
    """
  }

  static func analysisResult(from response: String, pages: [OCRPageSnapshot]) throws -> AnalysisResult {
    let jsonText = try jsonObjectText(from: response)
    guard let data = jsonText.data(using: .utf8) else {
      throw DocumentAnalyzerError.malformedModelOutput
    }

    let decoded: GemmaAnalysisResponse
    do {
      decoded = try JSONDecoder().decode(GemmaAnalysisResponse.self, from: data)
    } catch {
      throw DocumentAnalyzerError.malformedModelOutput
    }

    let validObservationIDs = Set(pages.flatMap(\.observations).map(\.id))
    let parser = DateRangeParser()
    let tasks = decoded.tasks.compactMap { task -> TaskDraft? in
      let title = FoundationModelsDocumentAnalyzer.compactGeneratedTitle(task.title)
      let note = task.note.trimmingCharacters(in: .whitespacesAndNewlines)
      let evidenceText = task.evidenceText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        !title.isEmpty,
        !note.isEmpty,
        !evidenceText.isEmpty,
        let evidenceObservationID = UUID(uuidString: task.evidenceObservationID),
        validObservationIDs.contains(evidenceObservationID)
      else {
        return nil
      }

      let modelDate = Self.date(from: task.date)
      let parsedDate = parser.parse([note, evidenceText].joined(separator: "\n"))
      return TaskDraft(
        title: String(title.prefix(15)),
        note: note,
        dueStart: modelDate ?? parsedDate.start,
        dueEnd: parsedDate.end,
        evidenceText: evidenceText,
        evidenceObservationID: evidenceObservationID
      )
    }

    guard !decoded.tasks.isEmpty, tasks.count == decoded.tasks.count, !tasks.isEmpty else {
      throw DocumentAnalyzerError.malformedModelOutput
    }

    return AnalysisResult(
      documentTitle: documentTitle(from: decoded.documentTitle, pages: pages),
      tasks: tasks
    )
  }

  private static func jsonObjectText(from response: String) throws -> String {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let start = trimmed.firstIndex(of: "{"),
      let end = trimmed.lastIndex(of: "}"),
      start <= end
    else {
      throw DocumentAnalyzerError.malformedModelOutput
    }
    return String(trimmed[start...end])
  }

  private static func date(from text: String?) -> Date? {
    guard
      let text,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: text)
  }

  private static func documentTitle(from title: String?, pages: [OCRPageSnapshot]) -> String {
    let modelTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !modelTitle.isEmpty {
      return String(modelTitle.prefix(20))
    }
    return FoundationModelsDocumentAnalyzer.documentTitle(from: "", pages: pages)
  }
}

private struct GemmaAnalysisResponse: Decodable {
  var documentTitle: String?
  var tasks: [GemmaTaskResponse]
}

private struct GemmaTaskResponse: Decodable {
  var title: String
  var note: String
  var date: String?
  var evidenceText: String
  var evidenceObservationID: String
}

#if canImport(LiteRTLM)
private struct LiteRTGemmaTextGenerator: GemmaTextGenerating {
  var modelURL: URL

  func generate(prompt: String) async throws -> String {
    do {
      let config = try EngineConfig(
        modelPath: modelURL.path,
        backend: .gpu,
        maxNumTokens: 2048,
        cacheDir: NSTemporaryDirectory()
      )
      let engine = Engine(engineConfig: config)
      try engine.initialize()
      let conversation = try engine.createConversation()
      let response = try await conversation.sendMessage(Message(prompt))
      let content = response.toString.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !content.isEmpty else {
        throw DocumentAnalyzerError.malformedModelOutput
      }
      return content
    } catch let error as DocumentAnalyzerError {
      throw error
    } catch {
      throw DocumentAnalyzerError.modelLoadFailed
    }
  }
}
#endif

struct AppleIntelligenceAvailability: Sendable {
  var isSupportedOverride: Bool?

  var isSupported: Bool {
    if let isSupportedOverride {
      return isSupportedOverride
    }

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
    let ocrText = Self.plainOCRText(from: pages)
    guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    let summary = try await foundationResponse(
      instructions: Self.summaryPrompt,
      input: ocrText
    )
    let taskText = try await foundationResponse(
      instructions: "保護者のタスクを抽出してください",
      input: summary
    )
    let taskNotes = Self.lines(from: taskText)
    guard !taskNotes.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    var drafts: [TaskDraft] = []
    for note in taskNotes {
      let titleResponse = try await foundationResponse(
        instructions: "タスクを1行20文字以内で生成してください。",
        input: note
      )
      let title = Self.compactGeneratedTitle(titleResponse)
      guard !title.isEmpty else {
        continue
      }

      let evidenceText = try await foundationResponse(
        instructions: "OCR文章から「\(note)」を抽出しました。抽出元の根拠となった文章をOCR文章からだしてください。",
        input: ocrText
      )
      let evidence = Self.compactEvidenceText(evidenceText)
      guard !evidence.isEmpty else {
        throw DocumentAnalyzerError.malformedModelOutput
      }

      let parsedDate = DateRangeParser().parse(note)
      drafts.append(TaskDraft(
        title: title,
        note: note,
        dueStart: parsedDate.start,
        dueEnd: parsedDate.end,
        evidenceText: evidence,
        evidenceObservationID: Self.bestObservationID(for: evidence, in: pages)
      ))
    }

    guard !drafts.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    return AnalysisResult(
      documentTitle: Self.documentTitle(from: summary, pages: pages),
      tasks: drafts
    )
  }

  private func foundationResponse(instructions: String, input: String) async throws -> String {
    let session = LanguageModelSession(
      model: .default,
      instructions: instructions
    )
    let response = try await session.respond(to: input)
    let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      throw DocumentAnalyzerError.malformedModelOutput
    }
    return content
  }
  #endif

  private static var summaryPrompt: String {
    let customPrompt = UserDefaults.standard.string(forKey: "developmentSummaryPrompt")?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return customPrompt.isEmpty ? defaultTaskExtractionInstructions : customPrompt
  }

  static let defaultTaskExtractionInstructions = "要約してください"

  static func plainOCRText(from pages: [OCRPageSnapshot]) -> String {
    pages
      .sorted { $0.pageIndex < $1.pageIndex }
      .map { page in
        if page.observations.isEmpty {
          return page.text
        }
        return page.observations.map(\.text).joined(separator: "\n")
      }
      .joined(separator: "\n\n")
  }

  static func lines(from text: String) -> [String] {
    text
      .components(separatedBy: .newlines)
      .map { cleanedListLine($0) }
      .filter { !$0.isEmpty && !isEmptyModelAnswer($0) }
  }

  static func compactGeneratedTitle(_ text: String) -> String {
    let title = (lines(from: text).first ?? cleanedListLine(text))
      .replacingOccurrences(of: "してください", with: "")
      .replacingOccurrences(of: "お願いします", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return String(title.prefix(20))
  }

  static func compactEvidenceText(_ text: String) -> String {
    lines(from: text).first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func bestObservationID(for evidence: String, in pages: [OCRPageSnapshot]) -> UUID? {
    let candidates = pages.flatMap(\.observations)
    guard !candidates.isEmpty else {
      return nil
    }

    let normalizedEvidence = normalizedText(evidence)
    guard !normalizedEvidence.isEmpty else {
      return nil
    }

    let bestMatch = candidates
      .map { observation in
        (id: observation.id, score: similarityScore(normalizedEvidence, normalizedText(observation.text)))
      }
      .max { $0.score < $1.score }

    guard let bestMatch, bestMatch.score > 0 else {
      return nil
    }
    return bestMatch.id
  }

  static func documentTitle(from summary: String, pages: [OCRPageSnapshot]) -> String {
    let summaryTitle = lines(from: summary).first ?? ""
    if !summaryTitle.isEmpty {
      return String(summaryTitle.prefix(20))
    }

    let ocrTitle = plainOCRText(from: pages)
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "プリント"
    return String(ocrTitle.prefix(20))
  }

  private static func cleanedListLine(_ text: String) -> String {
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^\s*(?:[-・*]|[0-9０-９]+[.)．、])\s*"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return line
    }
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    return regex
      .stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isEmptyModelAnswer(_ text: String) -> Bool {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return ["ありません", "なし", "無し", "該当なし", "タスクなし"].contains(normalized)
  }

  private static func normalizedText(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .punctuationCharacters)
  }

  private static func similarityScore(_ lhs: String, _ rhs: String) -> Int {
    guard !lhs.isEmpty, !rhs.isEmpty else {
      return 0
    }
    if lhs == rhs {
      return Int.max
    }
    if lhs.contains(rhs) || rhs.contains(lhs) {
      return Swift.max(lhs.count, rhs.count)
    }

    let lhsCharacters = Array(lhs)
    let rhsCharacters = Array(rhs)
    var lengths = Array(repeating: Array(repeating: 0, count: rhsCharacters.count + 1), count: lhsCharacters.count + 1)
    var best = 0

    for lhsIndex in lhsCharacters.indices {
      for rhsIndex in rhsCharacters.indices where lhsCharacters[lhsIndex] == rhsCharacters[rhsIndex] {
        let length = lengths[lhsIndex][rhsIndex] + 1
        lengths[lhsIndex + 1][rhsIndex + 1] = length
        best = Swift.max(best, length)
      }
    }
    return best
  }
}
