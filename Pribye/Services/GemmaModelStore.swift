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

  private var applicationSupportURLOverride: URL?
  private var fileManager: FileManager { .default }

  init(applicationSupportURL: URL? = nil) {
    self.applicationSupportURLOverride = applicationSupportURL
  }

  func status() -> GemmaModelStatus {
    guard fileManager.fileExists(atPath: modelFileURL.path) else {
      return .notDownloaded
    }
    return (try? sha256Hex(for: modelFileURL)) == Self.modelSHA256 ? .ready : .invalid
  }

  func downloadModel() async throws {
    guard let downloadURL = URL(string: Self.modelDownloadURLString) else {
      throw GemmaModelStoreError.invalidDownloadURL
    }

    try fileManager.createDirectory(
      at: modelDirectoryURL,
      withIntermediateDirectories: true
    )

    let temporaryURL = modelDirectoryURL.appendingPathComponent("\(Self.modelFileName).download")
    if fileManager.fileExists(atPath: temporaryURL.path) {
      try fileManager.removeItem(at: temporaryURL)
    }

    let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL)
    try fileManager.moveItem(at: downloadedURL, to: temporaryURL)

    guard try sha256Hex(for: temporaryURL) == Self.modelSHA256 else {
      try? fileManager.removeItem(at: temporaryURL)
      throw GemmaModelStoreError.invalidChecksum
    }

    if fileManager.fileExists(atPath: modelFileURL.path) {
      try fileManager.removeItem(at: modelFileURL)
    }
    try fileManager.moveItem(at: temporaryURL, to: modelFileURL)
  }

  func deleteModel() throws {
    guard fileManager.fileExists(atPath: modelFileURL.path) else {
      return
    }
    try fileManager.removeItem(at: modelFileURL)
  }

  var modelFileURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName)
  }

  private var modelDirectoryURL: URL {
    let applicationSupportURL = applicationSupportURLOverride
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return applicationSupportURL.appendingPathComponent("Models", isDirectory: true)
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
