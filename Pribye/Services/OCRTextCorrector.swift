import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

protocol OCRTextCorrector: Sendable {
  func correct(pages: [OCRPageSnapshot]) async -> [OCRPageSnapshot]
}

struct FoundationModelsOCRTextCorrector: OCRTextCorrector {
  private let availability: AppleIntelligenceAvailability

  init(availability: AppleIntelligenceAvailability = AppleIntelligenceAvailability()) {
    self.availability = availability
  }

  func correct(pages: [OCRPageSnapshot]) async -> [OCRPageSnapshot] {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), availability.isSupported {
      do {
        return try await correctWithFoundationModels(pages: pages)
      } catch {
        return pages
      }
    }
    #endif
    return pages
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private func correctWithFoundationModels(pages: [OCRPageSnapshot]) async throws -> [OCRPageSnapshot] {
    let session = LanguageModelSession(
      model: .default,
      instructions: """
      あなたは日本語の学校・幼稚園プリントのOCR結果を補正します。
      OCRの読み間違いだけを直し、元の文にない情報は追加しないでください。
      日付、数量、固有名詞、提出物は推測で変更しないでください。
      observation IDは必ず入力と同じものを返してください。
      """
    )

    let response = try await session.respond(
      to: makeCorrectionPrompt(pages: pages),
      generating: FoundationModelOCRCorrectionOutput.self,
      includeSchemaInPrompt: true
    )

    return response.content.correctedSnapshots(from: pages)
  }

  private func makeCorrectionPrompt(pages: [OCRPageSnapshot]) -> String {
    let pageText = pages
      .map { page in
        let observations = page.observations
          .map { "- id: \($0.id.uuidString)\n  text: \($0.text)" }
          .joined(separator: "\n")
        return "Page \(page.pageIndex + 1):\n\(observations)"
      }
      .joined(separator: "\n\n")

    return """
    次のOCR行を、学校・幼稚園プリントとして自然な日本語に補正してください。

    例:
    OCR: シャンプー・コンディショナーや食器用洗剤等の空き容器をきれいに洗って、2タと容器に記名の上持たせてください
    補正: シャンプー・コンディショナーや食器用洗剤等の空き容器をきれいに洗って、フタと容器に記名の上持たせてください

    ルール:
    - 明らかなOCR誤認だけを直す
    - 意味が不明な箇所は元のままにする
    - 行数とobservation IDの対応を維持する
    - correctedTextには補正後の1行だけを入れる

    OCR:
    \(pageText)
    """
  }
  #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Corrected OCR text for printed Japanese school notices")
private struct FoundationModelOCRCorrectionOutput {
  @Guide(description: "Corrected OCR lines, preserving the original observation IDs")
  var observations: [FoundationModelCorrectedOCRObservation]

  func correctedSnapshots(from originalPages: [OCRPageSnapshot]) -> [OCRPageSnapshot] {
    var correctedTextByID: [UUID: String] = [:]
    for observation in observations {
      guard let id = UUID(uuidString: observation.id) else {
        continue
      }
      let correctedText = observation.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !correctedText.isEmpty {
        correctedTextByID[id] = correctedText
      }
    }

    return originalPages.map { page in
      let correctedObservations = page.observations.map { observation in
        OCRObservationSnapshot(
          id: observation.id,
          text: correctedTextByID[observation.id] ?? observation.text
        )
      }
      return OCRPageSnapshot(
        pageIndex: page.pageIndex,
        text: correctedObservations.map(\.text).joined(separator: "\n"),
        observations: correctedObservations
      )
    }
  }
}

@available(iOS 26.0, *)
@Generable(description: "One corrected OCR line")
private struct FoundationModelCorrectedOCRObservation {
  @Guide(description: "The UUID string of the original OCR observation")
  var id: String

  @Guide(description: "The corrected text for this OCR line")
  var correctedText: String
}
#endif
