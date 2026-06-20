import XCTest
@testable import Pribye

final class DocumentAnalyzerTests: XCTestCase {
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
