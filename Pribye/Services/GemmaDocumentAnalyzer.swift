import Foundation
#if canImport(LiteRTLM)
import LiteRTLM
#endif

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
private extension GemmaInferenceBackend {
  var liteRTBackend: Backend {
    switch self {
    case .gpu:
      return .gpu
    case .cpu:
      return .cpu()
    }
  }
}

private struct LiteRTGemmaTextGenerator: GemmaTextGenerating {
  var modelURL: URL
  private let backendSelector: GemmaInferenceBackendSelector

  init(
    modelURL: URL,
    backendSelector: GemmaInferenceBackendSelector = GemmaInferenceBackendSelector()
  ) {
    self.modelURL = modelURL
    self.backendSelector = backendSelector
  }

  func generate(prompt: String) async throws -> String {
    var lastError: Error?

    for backend in backendSelector.orderedBackends() {
      do {
        let content = try await generate(prompt: prompt, backend: backend)
        backendSelector.recordSuccess(backend)
        NSLog("%@", "Gemma inference succeeded with \(backend.rawValue) backend.")
        return content
      } catch {
        lastError = error
        NSLog("%@", "Gemma inference failed with \(backend.rawValue) backend: \(String(describing: error))")
      }
    }

    if let error = lastError as? DocumentAnalyzerError {
      throw error
    }
    throw DocumentAnalyzerError.modelLoadFailed
  }

  private func generate(
    prompt: String,
    backend: GemmaInferenceBackend
  ) async throws -> String {
    do {
      let config = try EngineConfig(
        modelPath: modelURL.path,
        backend: backend.liteRTBackend,
        maxNumTokens: 2048,
        cacheDir: NSTemporaryDirectory()
      )
      let engine = Engine(engineConfig: config)
      try await engine.initialize()
      let conversation = try await engine.createConversation()
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
