import CryptoKit
import Foundation

enum GemmaModelStoreError: Error, Equatable {
  case invalidDownloadURL
  case invalidChecksum
  case fileOperationFailed
}

enum GemmaModelStatus: Equatable {
  case notDownloaded
  case ready
  case invalid
}

struct GemmaModelStore: Sendable {
  static let shared = GemmaModelStore()

  static let modelFileName = "gemma-4-E4B-it.litertlm"
  static let modelSHA256 = "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
  static let modelDownloadURLString = "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
  static let estimatedDownloadSizeBytes: Int64 = 3_660_000_000

  private static let verificationMarkerSuffix = ".sha256"
  private static let stagedDownloadSuffix = ".download"

  private var applicationSupportURLOverride: URL?
  private var fileManager: FileManager { .default }

  init(applicationSupportURL: URL? = nil) {
    self.applicationSupportURLOverride = applicationSupportURL
  }

  func status() -> GemmaModelStatus {
    guard fileManager.fileExists(atPath: modelFileURL.path) else {
      return .notDownloaded
    }

    guard
      let marker = try? String(contentsOf: verificationMarkerURL, encoding: .utf8),
      marker.trimmingCharacters(in: .whitespacesAndNewlines) == Self.modelSHA256
    else {
      return .invalid
    }

    return .ready
  }

  var hasModelFile: Bool {
    fileManager.fileExists(atPath: modelFileURL.path)
  }

  var modelFileSize: Int64? {
    guard
      let attributes = try? fileManager.attributesOfItem(atPath: modelFileURL.path),
      let size = attributes[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  func prepareForDownload() throws {
    try fileManager.createDirectory(
      at: modelDirectoryURL,
      withIntermediateDirectories: true
    )

    try removeIfPresent(at: stagedDownloadURL)
    try removeIfPresent(at: verificationMarkerURL)
  }

  func stageDownloadedFile(from downloadedURL: URL) throws -> URL {
    try fileManager.createDirectory(
      at: modelDirectoryURL,
      withIntermediateDirectories: true
    )
    try removeIfPresent(at: stagedDownloadURL)
    try fileManager.moveItem(at: downloadedURL, to: stagedDownloadURL)
    return stagedDownloadURL
  }

  func validateStagedModelAndInstall() throws {
    try Task.checkCancellation()

    guard fileManager.fileExists(atPath: stagedDownloadURL.path) else {
      throw GemmaModelStoreError.fileOperationFailed
    }

    guard try sha256Hex(for: stagedDownloadURL) == Self.modelSHA256 else {
      try? removeIfPresent(at: stagedDownloadURL)
      throw GemmaModelStoreError.invalidChecksum
    }

    try Task.checkCancellation()
    try removeIfPresent(at: modelFileURL)
    try fileManager.moveItem(at: stagedDownloadURL, to: modelFileURL)
    try writeVerificationMarker()
  }

  func validateExistingModel() throws {
    try Task.checkCancellation()

    guard fileManager.fileExists(atPath: modelFileURL.path) else {
      throw GemmaModelStoreError.fileOperationFailed
    }

    guard try sha256Hex(for: modelFileURL) == Self.modelSHA256 else {
      try? removeIfPresent(at: verificationMarkerURL)
      throw GemmaModelStoreError.invalidChecksum
    }

    try Task.checkCancellation()
    try writeVerificationMarker()
  }

  func deleteModel() throws {
    try removeIfPresent(at: stagedDownloadURL)
    try removeIfPresent(at: verificationMarkerURL)
    try removeIfPresent(at: modelFileURL)
  }

  func deleteStagedDownload() throws {
    try removeIfPresent(at: stagedDownloadURL)
  }

  var modelFileURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName)
  }

  var stagedDownloadURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName + Self.stagedDownloadSuffix)
  }

  var verificationMarkerURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName + Self.verificationMarkerSuffix)
  }

  private var modelDirectoryURL: URL {
    let applicationSupportURL = applicationSupportURLOverride
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return applicationSupportURL.appendingPathComponent("Models", isDirectory: true)
  }

  private func writeVerificationMarker() throws {
    try Self.modelSHA256.write(
      to: verificationMarkerURL,
      atomically: true,
      encoding: .utf8
    )
  }

  private func removeIfPresent(at url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else {
      return
    }
    try fileManager.removeItem(at: url)
  }

  private func sha256Hex(for fileURL: URL) throws -> String {
    guard let stream = InputStream(url: fileURL) else {
      throw GemmaModelStoreError.fileOperationFailed
    }

    stream.open()
    defer { stream.close() }

    var hasher = SHA256()
    let bufferSize = 1024 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
      try Task.checkCancellation()

      let readCount = stream.read(buffer, maxLength: bufferSize)
      if readCount < 0 {
        throw stream.streamError ?? GemmaModelStoreError.fileOperationFailed
      }
      if readCount == 0 {
        break
      }
      hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: readCount))
    }

    return hasher
      .finalize()
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
