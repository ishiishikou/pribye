#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
func makeProbeSession() -> LanguageModelSession {
  LanguageModelSession(
    model: .default,
    instructions: "Probe Foundation Models structured generation availability."
  )
}

@available(iOS 26.0, *)
@Generable(description: "Minimal Foundation Models probe output")
struct FoundationModelsProbeOutput {
  @Guide(description: "A short probe response")
  var text: String
}

@available(iOS 26.0, *)
func probeStructuredTextResponse() async throws -> FoundationModelsProbeOutput {
  let session = makeProbeSession()
  let response = try await session.respond(
    to: "Return a short Japanese sentence.",
    generating: FoundationModelsProbeOutput.self,
    includeSchemaInPrompt: true
  )
  return response.content
}
#else
#error("FoundationModels is not available in this SDK.")
#endif
