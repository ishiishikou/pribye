import Foundation

private struct GemmaModelDownloadBridgeError: LocalizedError, Sendable {
  let message: String

  var errorDescription: String? {
    message
  }
}

extension GemmaModelStore {
  /// Compatibility entry point for the capture flow.
  ///
  /// The background transfer, verification, and persisted state remain owned by
  /// `GemmaModelDownloadManager`; this method only waits for that manager to
  /// reach a terminal state so the existing capture UI can continue to await it.
  @MainActor
  func downloadModel() async throws {
    let manager = GemmaModelDownloadManager.shared

    if manager.modelStatus == .ready {
      return
    }

    manager.startDownload(allowsCellularAccess: false)

    while true {
      try Task.checkCancellation()

      switch manager.state.phase {
      case .downloading, .verifying:
        try await ContinuousClock().sleep(for: .milliseconds(200))

      case .failed(let message):
        throw GemmaModelDownloadBridgeError(message: message)

      case .idle:
        manager.refreshModelStatus()

        if manager.modelStatus == .ready {
          return
        }

        if manager.state.isActive {
          try await ContinuousClock().sleep(for: .milliseconds(200))
          continue
        }

        throw GemmaModelDownloadBridgeError(
          message: manager.statusMessage ?? "モデルのダウンロードまたは検証に失敗しました。"
        )
      }
    }
  }
}
