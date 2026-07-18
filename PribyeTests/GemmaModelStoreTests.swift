import Foundation
import XCTest
@testable import Pribye

final class GemmaModelStoreTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
    temporaryDirectory = nil
  }

  func testStatusIsNotDownloadedWithoutModelFile() {
    let store = GemmaModelStore(applicationSupportURL: temporaryDirectory)

    XCTAssertEqual(store.status(), .notDownloaded)
  }

  func testStatusIsInvalidWithoutVerificationMarker() throws {
    let store = GemmaModelStore(applicationSupportURL: temporaryDirectory)
    try FileManager.default.createDirectory(
      at: store.modelFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(to: store.modelFileURL)

    XCTAssertEqual(store.status(), .invalid)
  }

  func testStatusIsReadyWithVerificationMarker() throws {
    let store = GemmaModelStore(applicationSupportURL: temporaryDirectory)
    try FileManager.default.createDirectory(
      at: store.modelFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(to: store.modelFileURL)
    try GemmaModelStore.modelSHA256.write(
      to: store.verificationMarkerURL,
      atomically: true,
      encoding: .utf8
    )

    XCTAssertEqual(store.status(), .ready)
  }

  func testDeleteModelRemovesModelMarkerAndStagedDownload() throws {
    let store = GemmaModelStore(applicationSupportURL: temporaryDirectory)
    try FileManager.default.createDirectory(
      at: store.modelFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(to: store.modelFileURL)
    try Data("partial".utf8).write(to: store.stagedDownloadURL)
    try GemmaModelStore.modelSHA256.write(
      to: store.verificationMarkerURL,
      atomically: true,
      encoding: .utf8
    )

    try store.deleteModel()

    XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelFileURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagedDownloadURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.verificationMarkerURL.path))
  }
}
