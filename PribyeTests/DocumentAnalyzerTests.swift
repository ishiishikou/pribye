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
}

private struct StubDocumentAnalyzer: DocumentAnalyzer {
  var result: AnalysisResult

  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult {
    result
  }
}
