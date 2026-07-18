import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct OCRPageSnapshot: Equatable, Sendable {
  var pageIndex: Int
  var text: String
  var observations: [OCRObservationSnapshot]
}

struct OCRObservationSnapshot: Equatable, Sendable {
  var id: UUID
  var text: String
}

struct TaskDraft: Equatable, Sendable {
  var title: String
  var note: String
  var dueStart: Date?
  var dueEnd: Date?
  var evidenceText: String
  var evidenceObservationID: UUID?
}

struct AnalysisResult: Equatable, Sendable {
  var documentTitle: String
  var tasks: [TaskDraft]
}

enum DocumentAnalyzerError: Error, Equatable {
  case noActionableTasks
  case unsupportedDevice
  case modelNotReady
  case modelLoadFailed
  case malformedModelOutput
}

protocol DocumentAnalyzer: Sendable {
  var shouldDeduplicateTasks: Bool { get }
  func analyze(pages: [OCRPageSnapshot]) async throws -> AnalysisResult
}

extension DocumentAnalyzer {
  var shouldDeduplicateTasks: Bool { true }
}

protocol GemmaTextGenerating: Sendable {
  func generate(prompt: String) async throws -> String
}

enum GemmaInferenceBackend: String, CaseIterable, Sendable {
  case gpu
  case cpu
}

struct GemmaBackendEnvironment: Equatable, Sendable {
  var hardwareIdentifier: String
  var operatingSystemVersion: String
  var liteRTLMVersion: String
  var modelSHA256: String

  static var current: GemmaBackendEnvironment {
    GemmaBackendEnvironment(
      hardwareIdentifier: currentHardwareIdentifier(),
      operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      liteRTLMVersion: "0.14.0",
      modelSHA256: GemmaModelStore.modelSHA256
    )
  }

  fileprivate var preferenceKey: String {
    [
      "com.pribye.gemma-inference-backend",
      hardwareIdentifier,
      operatingSystemVersion,
      liteRTLMVersion,
      modelSHA256
    ].joined(separator: "|")
  }

  private static func currentHardwareIdentifier() -> String {
    #if targetEnvironment(simulator)
    if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
       !identifier.isEmpty {
      return identifier
    }
    #endif

    #if canImport(Darwin)
    var systemInfo = utsname()
    guard uname(&systemInfo) == 0 else {
      return "unknown"
    }
    let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
    return withUnsafePointer(to: &systemInfo.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
        String(cString: $0)
      }
    }
    #else
    return "unknown"
    #endif
  }
}

struct GemmaBackendPreferenceStore: @unchecked Sendable {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func preferredBackend(for environment: GemmaBackendEnvironment) -> GemmaInferenceBackend? {
    guard let rawValue = defaults.string(forKey: environment.preferenceKey) else {
      return nil
    }
    return GemmaInferenceBackend(rawValue: rawValue)
  }

  func save(_ backend: GemmaInferenceBackend, for environment: GemmaBackendEnvironment) {
    defaults.set(backend.rawValue, forKey: environment.preferenceKey)
  }
}

struct GemmaInferenceBackendSelector: Sendable {
  private let environment: GemmaBackendEnvironment
  private let preferenceStore: GemmaBackendPreferenceStore

  init(
    environment: GemmaBackendEnvironment = .current,
    preferenceStore: GemmaBackendPreferenceStore = GemmaBackendPreferenceStore()
  ) {
    self.environment = environment
    self.preferenceStore = preferenceStore
  }

  func orderedBackends() -> [GemmaInferenceBackend] {
    guard let preferredBackend = preferenceStore.preferredBackend(for: environment) else {
      return [.gpu, .cpu]
    }
    return [preferredBackend] + GemmaInferenceBackend.allCases.filter { $0 != preferredBackend }
  }

  func recordSuccess(_ backend: GemmaInferenceBackend) {
    preferenceStore.save(backend, for: environment)
  }
}
