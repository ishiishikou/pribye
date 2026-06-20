import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceChatError: LocalizedError, Equatable {
  case emptyPrompt
  case emptyOCRText
  case unsupportedDevice

  var errorDescription: String? {
    switch self {
    case .emptyPrompt:
      return "プロンプトを入力してください。"
    case .emptyOCRText:
      return "OCR文章を入力してください。"
    case .unsupportedDevice:
      return "Apple Intelligenceをオンにしてから利用してください。"
    }
  }
}

struct AppleIntelligenceChatService: Sendable {
  private let availability: AppleIntelligenceAvailability

  init(availability: AppleIntelligenceAvailability = AppleIntelligenceAvailability()) {
    self.availability = availability
  }

  func respond(prompt: String, ocrText: String) async throws -> String {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty else {
      throw AppleIntelligenceChatError.emptyPrompt
    }

    let trimmedOCRText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOCRText.isEmpty else {
      throw AppleIntelligenceChatError.emptyOCRText
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), availability.isSupported {
      let session = LanguageModelSession(
        model: .default,
        instructions: trimmedPrompt
      )
      let response = try await session.respond(to: trimmedOCRText)
      return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    throw AppleIntelligenceChatError.unsupportedDevice
  }
}
