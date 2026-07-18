import Foundation
#if canImport(FoundationModels)
import FoundationModels
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
