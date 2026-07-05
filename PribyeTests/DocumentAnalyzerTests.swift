import XCTest
@testable import Pribye

final class DocumentAnalyzerTests: XCTestCase {
  func testTaskExtractionResponseLinesRemoveListMarkers() {
    let lines = FoundationModelsDocumentAnalyzer.lines(from: """
    1. 6月20日までに体操服を持参する
    ・空き容器に記名して持参する
    - 集金袋を提出する
    """)

    XCTAssertEqual(lines, [
      "6月20日までに体操服を持参する",
      "空き容器に記名して持参する",
      "集金袋を提出する"
    ])
  }

  func testGeneratedTitleIsCompactAndRemovesRequestExpression() {
    let title = FoundationModelsDocumentAnalyzer.compactGeneratedTitle("体操服を持参してください。")

    XCTAssertEqual(title, "体操服を持参")
  }

  func testTaskExtractionResponseLinesIgnoreEmptyTaskAnswer() {
    let lines = FoundationModelsDocumentAnalyzer.lines(from: "タスクなし")

    XCTAssertTrue(lines.isEmpty)
  }

  func testBestObservationIDMatchesEvidenceText() {
    let firstID = UUID()
    let secondID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ",
        observations: [
          OCRObservationSnapshot(id: firstID, text: "6月20日までに体操服を持参してください。"),
          OCRObservationSnapshot(id: secondID, text: "空き容器を洗って記名の上、持たせてください。")
        ]
      )
    ]

    let matchedID = FoundationModelsDocumentAnalyzer.bestObservationID(
      for: "空き容器を洗って記名の上、持たせてください。",
      in: pages
    )

    XCTAssertEqual(matchedID, secondID)
  }

  @MainActor
  func testPipelineStoresGeneratedTitleNoteAndEvidenceWithoutOverwritingEvidence() async throws {
    let observationID = UUID()
    let note = "6月20日までに体操服を持参する"
    let evidence = "6月20日までに体操服を持参してください。"
    let analyzer = StubDocumentAnalyzer(result: AnalysisResult(
      documentTitle: "体育授業のお知らせ",
      tasks: [
        TaskDraft(
          title: "体操服を持参",
          note: note,
          dueStart: nil,
          dueEnd: nil,
          evidenceText: evidence,
          evidenceObservationID: observationID
        )
      ]
    ))
    let pipeline = DocumentAnalysisPipeline(analyzer: analyzer)
    let document = DocumentRecord()
    let snapshots = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: evidence,
        observations: [
          OCRObservationSnapshot(id: observationID, text: evidence)
        ]
      )
    ]

    try await pipeline.applyAnalysis(to: document, snapshots: snapshots)

    XCTAssertEqual(document.title, "体育授業のお知らせ")
    XCTAssertEqual(document.tasks.count, 1)
    XCTAssertEqual(document.tasks.first?.title, "体操服を持参")
    XCTAssertEqual(document.tasks.first?.note, note)
    XCTAssertEqual(document.tasks.first?.evidenceText, evidence)
    XCTAssertEqual(document.tasks.first?.evidenceObservationID, observationID)
    XCTAssertEqual(document.status, .ready)
  }

  func testAppleIntelligenceChatFailsWhenPromptIsEmpty() async {
    let service = AppleIntelligenceChatService(
      availability: AppleIntelligenceAvailability(isSupportedOverride: true)
    )

    do {
      _ = try await service.respond(prompt: " ", ocrText: "OCR文章")
      XCTFail("Expected emptyPrompt")
    } catch {
      XCTAssertEqual(error as? AppleIntelligenceChatError, .emptyPrompt)
    }
  }

  func testAppleIntelligenceChatFailsWhenOCRTextIsEmpty() async {
    let service = AppleIntelligenceChatService(
      availability: AppleIntelligenceAvailability(isSupportedOverride: true)
    )

    do {
      _ = try await service.respond(prompt: "プロンプト", ocrText: " ")
      XCTFail("Expected emptyOCRText")
    } catch {
      XCTAssertEqual(error as? AppleIntelligenceChatError, .emptyOCRText)
    }
  }

  func testAppleIntelligenceChatFailsWhenAppleIntelligenceIsUnavailable() async {
    let service = AppleIntelligenceChatService(
      availability: AppleIntelligenceAvailability(isSupportedOverride: false)
    )

    do {
      _ = try await service.respond(prompt: "プロンプト", ocrText: "OCR文章")
      XCTFail("Expected unsupportedDevice")
    } catch {
      XCTAssertEqual(error as? AppleIntelligenceChatError, .unsupportedDevice)
    }
  }

  func testFoundationModelsAnalyzerFailsWhenAppleIntelligenceIsUnavailable() async {
    let analyzer = FoundationModelsDocumentAnalyzer(
      availability: AppleIntelligenceAvailability(isSupportedOverride: false)
    )
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ\n6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: UUID(), text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]

    do {
      _ = try await analyzer.analyze(pages: pages)
      XCTFail("Expected unsupportedDevice")
    } catch {
      XCTAssertEqual(error as? DocumentAnalyzerError, .unsupportedDevice)
    }
  }

  func testGemmaAnalyzerFailsWhenModelIsNotReady() async {
    let modelStore = GemmaModelStore(
      applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    )
    let analyzer = GemmaDocumentAnalyzer(modelStore: modelStore)
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ\n6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: UUID(), text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]

    do {
      _ = try await analyzer.analyze(pages: pages)
      XCTFail("Expected modelNotReady")
    } catch {
      XCTAssertEqual(error as? DocumentAnalyzerError, .modelNotReady)
    }
  }

  func testGemmaAnalyzerUsesInjectedTextGenerator() async throws {
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参",
          "note": "6月20日までに体操服を持参する",
          "date": null,
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(observationID.uuidString)"
        }
      ]
    }
    """
    let generator = StubGemmaTextGenerator(response: response)
    let analyzer = GemmaDocumentAnalyzer(textGenerator: generator)

    let result = try await analyzer.analyze(pages: pages)
    let prompt = await generator.recordedPrompt()

    XCTAssertTrue(prompt?.contains("TARGET_PAGE pageIndex=0") ?? false)
    XCTAssertTrue(prompt?.contains(observationID.uuidString) ?? false)
    XCTAssertEqual(result.documentTitle, "体育授業のお知らせ")
    XCTAssertEqual(result.tasks.first?.title, "体操服を持参")
    XCTAssertEqual(result.tasks.first?.evidenceObservationID, observationID)
  }

  func testGemmaAnalysisResultParsesJSONOutput() throws {
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参してください",
          "note": "6月20日までに体操服を持参する",
          "date": null,
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(observationID.uuidString)"
        }
      ]
    }
    """

    let result = try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)

    XCTAssertEqual(result.documentTitle, "体育授業のお知らせ")
    XCTAssertEqual(result.tasks.count, 1)
    XCTAssertEqual(result.tasks.first?.title, "体操服を持参")
    XCTAssertEqual(result.tasks.first?.evidenceObservationID, observationID)
  }

  func testGemmaAnalysisResultExtractsJSONFromModelPreamble() throws {
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    以下のJSONで回答します。
    ```json
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参",
          "note": "6月20日までに体操服を持参する",
          "date": null,
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(observationID.uuidString)"
        }
      ]
    }
    ```
    """

    let result = try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)

    XCTAssertEqual(result.documentTitle, "体育授業のお知らせ")
    XCTAssertEqual(result.tasks.first?.title, "体操服を持参")
    XCTAssertEqual(result.tasks.first?.evidenceObservationID, observationID)
  }

  func testGemmaAnalysisResultUsesModelDateWhenPresent() throws {
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参",
          "note": "6月20日までに体操服を持参する",
          "date": "2026-06-25",
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(observationID.uuidString)"
        }
      ]
    }
    """

    let result = try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)

    XCTAssertEqual(result.tasks.first?.dueStart, date(year: 2026, month: 6, day: 25))
    XCTAssertNil(result.tasks.first?.dueEnd)
  }

  func testGemmaAnalysisResultFallsBackToLocalDateParserWhenModelDateIsMissing() throws {
    let observationID = UUID()
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: observationID, text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参",
          "note": "6月20日までに体操服を持参する",
          "date": null,
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(observationID.uuidString)"
        }
      ]
    }
    """

    let result = try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)

    XCTAssertEqual(component(.month, result.tasks.first?.dueStart), 6)
    XCTAssertEqual(component(.day, result.tasks.first?.dueStart), 20)
    XCTAssertNil(result.tasks.first?.dueEnd)
  }

  func testGemmaAnalysisResultRejectsUnknownObservationID() {
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "6月20日までに体操服を持参してください。",
        observations: [
          OCRObservationSnapshot(id: UUID(), text: "6月20日までに体操服を持参してください。")
        ]
      )
    ]
    let response = """
    {
      "documentTitle": "体育授業のお知らせ",
      "tasks": [
        {
          "title": "体操服を持参",
          "note": "6月20日までに体操服を持参する",
          "date": null,
          "evidenceText": "6月20日までに体操服を持参してください。",
          "evidenceObservationID": "\(UUID().uuidString)"
        }
      ]
    }
    """

    XCTAssertThrowsError(try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)) { error in
      XCTAssertEqual(error as? DocumentAnalyzerError, .malformedModelOutput)
    }
  }

  func testGemmaAnalysisResultRejectsEmptyTasks() {
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ",
        observations: [
          OCRObservationSnapshot(id: UUID(), text: "体育授業のお知らせ")
        ]
      )
    ]
    let response = #"{"documentTitle":"体育授業のお知らせ","tasks":[]}"#

    XCTAssertThrowsError(try GemmaDocumentAnalyzer.analysisResult(from: response, pages: pages)) { error in
      XCTAssertEqual(error as? DocumentAnalyzerError, .malformedModelOutput)
    }
  }

  func testGemmaAnalysisResultRejectsMalformedJSON() {
    let pages = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "体育授業のお知らせ",
        observations: [
          OCRObservationSnapshot(id: UUID(), text: "体育授業のお知らせ")
        ]
      )
    ]

    XCTAssertThrowsError(try GemmaDocumentAnalyzer.analysisResult(from: "not json", pages: pages)) { error in
      XCTAssertEqual(error as? DocumentAnalyzerError, .malformedModelOutput)
    }
  }

  @MainActor
  func testPipelineAnalyzesEachPageSeparatelyAndKeepsPerPageTasks() async throws {
    let sharedObservationID = UUID()
    let recorder = RecordingAnalyzerRecorder(resultsByPageIndex: [
      0: AnalysisResult(
        documentTitle: "1ページ目タイトル",
        tasks: [
          TaskDraft(
            title: "持ち物",
            note: "雑巾を持参する",
            dueStart: nil,
            dueEnd: nil,
            evidenceText: "雑巾を持参してください。",
            evidenceObservationID: sharedObservationID
          )
        ]
      ),
      1: AnalysisResult(
        documentTitle: "2ページ目タイトル",
        tasks: [
          TaskDraft(
            title: "持ち物",
            note: "上履きを持参する",
            dueStart: nil,
            dueEnd: nil,
            evidenceText: "上履きを持参してください。",
            evidenceObservationID: sharedObservationID
          )
        ]
      )
    ])
    let analyzer = RecordingDocumentAnalyzer(shouldDeduplicateTasks: false, recorder: recorder)
    let pipeline = DocumentAnalysisPipeline(analyzer: analyzer)
    let document = DocumentRecord()
    let snapshots = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "雑巾を持参する、",
        observations: [
          OCRObservationSnapshot(id: sharedObservationID, text: "雑巾を持参してください。")
        ]
      ),
      OCRPageSnapshot(
        pageIndex: 1,
        text: "上履きを持参してください。",
        observations: [
          OCRObservationSnapshot(id: sharedObservationID, text: "上履きを持参してください。")
        ]
      )
    ]

    try await pipeline.applyAnalysis(to: document, snapshots: snapshots)

    let recordedCalls = await recorder.recordedCalls()
    XCTAssertEqual(recordedCalls.count, 2)
    XCTAssertEqual(recordedCalls[0].map(\.pageIndex), [0, 1])
    XCTAssertEqual(recordedCalls[1].map(\.pageIndex), [1])
    XCTAssertEqual(document.title, "1ページ目タイトル")
    XCTAssertEqual(document.tasks.map(\.note), ["雑巾を持参する", "上履きを持参する"])
  }

  @MainActor
  func testPipelineAddsContextOnlyWhenTargetPageLooksIncomplete() async throws {
    let recorder = RecordingAnalyzerRecorder(resultsByPageIndex: [
      0: AnalysisResult(documentTitle: "1", tasks: [
        TaskDraft(
          title: "持参",
          note: "雑巾を持参する",
          dueStart: nil,
          dueEnd: nil,
          evidenceText: "雑巾を持参してください。",
          evidenceObservationID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
      ]),
      1: AnalysisResult(documentTitle: "2", tasks: [
        TaskDraft(
          title: "提出",
          note: "申込書を提出する",
          dueStart: nil,
          dueEnd: nil,
          evidenceText: "申込書を提出してください。",
          evidenceObservationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
      ])
    ])
    let analyzer = RecordingDocumentAnalyzer(shouldDeduplicateTasks: false, recorder: recorder)
    let pipeline = DocumentAnalysisPipeline(analyzer: analyzer)
    let document = DocumentRecord()
    let firstObservationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let secondObservationID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let snapshots = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "持ち物は次のとおり、",
        observations: [
          OCRObservationSnapshot(id: firstObservationID, text: "雑巾を持参してください。")
        ]
      ),
      OCRPageSnapshot(
        pageIndex: 1,
        text: "申込書を提出してください。",
        observations: [
          OCRObservationSnapshot(id: secondObservationID, text: "申込書を提出してください。")
        ]
      )
    ]

    try await pipeline.applyAnalysis(to: document, snapshots: snapshots)

    let recordedCalls = await recorder.recordedCalls()
    XCTAssertEqual(recordedCalls[0].count, 2)
    XCTAssertEqual(recordedCalls[1].count, 1)
  }

  @MainActor
  func testPipelineDropsTasksBackedOnlyByContextObservation() async throws {
    let targetObservationID = UUID()
    let contextObservationID = UUID()
    let recorder = RecordingAnalyzerRecorder(resultsByPageIndex: [
      0: AnalysisResult(
        documentTitle: "おたより",
        tasks: [
          TaskDraft(
            title: "提出",
            note: "申込書を提出する",
            dueStart: nil,
            dueEnd: nil,
            evidenceText: "申込書を提出してください。",
            evidenceObservationID: contextObservationID
          )
        ]
      ),
      1: AnalysisResult(
        documentTitle: "おたより",
        tasks: [
          TaskDraft(
            title: "持参",
            note: "申込書を提出する",
            dueStart: nil,
            dueEnd: nil,
            evidenceText: "申込書を提出してください。",
            evidenceObservationID: contextObservationID
          )
        ]
      )
    ])
    let analyzer = RecordingDocumentAnalyzer(shouldDeduplicateTasks: false, recorder: recorder)
    let pipeline = DocumentAnalysisPipeline(analyzer: analyzer)
    let document = DocumentRecord()
    let snapshots = [
      OCRPageSnapshot(
        pageIndex: 0,
        text: "提出物は次頁、",
        observations: [
          OCRObservationSnapshot(id: targetObservationID, text: "提出物は次頁、")
        ]
      ),
      OCRPageSnapshot(
        pageIndex: 1,
        text: "申込書を提出してください。",
        observations: [
          OCRObservationSnapshot(id: contextObservationID, text: "申込書を提出してください。")
        ]
      )
    ]

    try await pipeline.applyAnalysis(to: document, snapshots: snapshots)

    XCTAssertEqual(document.tasks.count, 1)
    XCTAssertEqual(document.tasks.first?.evidenceObservationID, contextObservationID)
    XCTAssertEqual(document.tasks.first?.note, "申込書を提出する")
  }
}

private struct StubDocumentAnalyzer: DocumentAnalyzer {
  var result: AnalysisResult

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    result
  }
}

private actor StubGemmaTextGenerator: GemmaTextGenerating {
  private let response: String
  private var prompt: String?

  init(response: String) {
    self.response = response
  }

  func generate(prompt: String) async throws -> String {
    self.prompt = prompt
    return response
  }

  func recordedPrompt() -> String? {
    prompt
  }
}

private actor RecordingAnalyzerRecorder {
  private let resultsByPageIndex: [Int: AnalysisResult]
  private var calls: [[OCRPageSnapshot]] = []

  init(resultsByPageIndex: [Int: AnalysisResult]) {
    self.resultsByPageIndex = resultsByPageIndex
  }

  func analyze(pages: [OCRPageSnapshot]) throws -> AnalysisResult {
    calls.append(pages)
    guard let result = resultsByPageIndex[pages[0].pageIndex] else {
      throw DocumentAnalyzerError.noActionableTasks
    }
    return result
  }

  func recordedCalls() -> [[OCRPageSnapshot]] {
    calls
  }
}

private struct RecordingDocumentAnalyzer: DocumentAnalyzer {
  var shouldDeduplicateTasks: Bool
  let recorder: RecordingAnalyzerRecorder

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    try await recorder.analyze(pages: pages)
  }
}

private func date(year: Int, month: Int, day: Int) -> Date {
  var components = DateComponents()
  components.calendar = Calendar(identifier: .gregorian)
  components.year = year
  components.month = month
  components.day = day
  return components.date!
}

private func component(_ component: Calendar.Component, _ date: Date?) -> Int? {
  guard let date else {
    return nil
  }
  return Calendar(identifier: .gregorian).component(component, from: date)
}
