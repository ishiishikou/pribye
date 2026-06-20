import XCTest
@testable import Pribye

final class DocumentAnalyzerTests: XCTestCase {
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
