import UIKit
import Vision

struct OCRPageResult: Sendable {
  var text: String
  var observations: [OCRLineResult]
}

struct OCRLineResult: Sendable {
  var text: String
  var confidence: Double
  var boundingBox: CGRect
}

@MainActor
protocol OCRServiceProtocol {
  func recognizeText(in image: UIImage) async throws -> OCRPageResult
}

@MainActor
final class VisionOCRService: OCRServiceProtocol {
  func recognizeText(in image: UIImage) async throws -> OCRPageResult {
    guard let cgImage = image.cgImage else {
      throw AnalysisFailureReason.imageError
    }

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        let recognized = (request.results as? [VNRecognizedTextObservation]) ?? []
        let lines = recognized.compactMap { observation -> OCRLineResult? in
          guard let candidate = observation.topCandidates(1).first else {
            return nil
          }
          return OCRLineResult(
            text: candidate.string,
            confidence: Double(candidate.confidence),
            boundingBox: observation.boundingBox
          )
        }

        continuation.resume(returning: OCRPageResult(
          text: lines.map(\.text).joined(separator: "\n"),
          observations: lines
        ))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["ja-JP", "en-US"]

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
