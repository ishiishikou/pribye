import CoreImage
import CryptoKit
import Foundation
import Photos
import UIKit

enum ImageAssetError: Error {
  case photoAccessDenied
  case assetNotFound
  case imageLoadFailed
  case correctionFailed
  case deletionFailed
}

struct SavedImageAsset: Sendable {
  var localIdentifier: String
  var imageHash: String
}

struct SavedLocalImageFile: Sendable {
  var filename: String
  var imageHash: String
}

struct ImageAssetStateResult {
  var image: UIImage?
  var state: SourceImageState
}

@MainActor
struct ImageAssetService {
  func saveImage(_ image: UIImage) async throws -> SavedImageAsset {
    let status = await requestPhotoWriteAccess()
    guard status == .authorized || status == .limited else {
      throw ImageAssetError.photoAccessDenied
    }

    let normalized = image.normalizedForProcessing()
    guard let imageData = normalized.pngData() else {
      throw ImageAssetError.imageLoadFailed
    }

    let hash = Self.hash(image: normalized)
    let identifier = try await Self.createPhotoAsset(with: imageData)

    return SavedImageAsset(localIdentifier: identifier, imageHash: hash)
  }

  func saveImageLocally(_ image: UIImage) throws -> SavedLocalImageFile {
    let normalized = image.normalizedForProcessing()
    guard let imageData = normalized.pngData() else {
      throw ImageAssetError.imageLoadFailed
    }

    let filename = "\(UUID().uuidString).png"
    do {
      let directory = try Self.localImageDirectory()
      let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
      try imageData.write(to: fileURL, options: .atomic)
    } catch {
      throw ImageAssetError.imageLoadFailed
    }

    return SavedLocalImageFile(
      filename: filename,
      imageHash: Self.hash(image: normalized)
    )
  }

  func loadVerifiedImage(for document: DocumentRecord) async -> ImageAssetStateResult {
    if let localImageFilename = document.localImageFilename {
      return loadVerifiedLocalImage(filename: localImageFilename, imageHash: document.imageHash)
    }
    return await loadVerifiedImage(identifier: document.photoAssetIdentifier, imageHash: document.imageHash)
  }

  func loadVerifiedImage(for page: PageRecord) async -> ImageAssetStateResult {
    if let localImageFilename = page.localImageFilename {
      return loadVerifiedLocalImage(filename: localImageFilename, imageHash: page.imageHash)
    }
    return await loadVerifiedImage(identifier: page.photoAssetIdentifier, imageHash: page.imageHash)
  }

  func deleteStoredImages(for document: DocumentRecord) async throws {
    let photoIdentifiers = Set(
      ([document.photoAssetIdentifier] + document.pages.map(\.photoAssetIdentifier))
        .compactMap { $0 }
    )
    if !photoIdentifiers.isEmpty {
      let status = await requestPhotoReadAccess()
      guard status == .authorized || status == .limited else {
        throw ImageAssetError.photoAccessDenied
      }
      try await Self.deletePhotoAssets(localIdentifiers: Array(photoIdentifiers))
    }

    let localFilenames = Set(
      ([document.localImageFilename] + document.pages.map(\.localImageFilename))
        .compactMap { $0 }
    )
    for filename in localFilenames {
      try Self.deleteLocalImage(filename: filename)
    }
  }

  private func loadVerifiedImage(identifier: String?, imageHash: String?) async -> ImageAssetStateResult {
    guard let identifier else {
      return ImageAssetStateResult(image: nil, state: .deleted)
    }

    let status = await requestPhotoReadAccess()
    guard status == .authorized || status == .limited else {
      return ImageAssetStateResult(image: nil, state: .permissionDenied)
    }

    do {
      let imageData = try await Self.loadImageData(localIdentifier: identifier)
      guard let image = UIImage(data: imageData)?.normalizedForProcessing() else {
        return ImageAssetStateResult(image: nil, state: .permissionDenied)
      }
      if let storedHash = imageHash, Self.hash(image: image) != storedHash {
        return ImageAssetStateResult(image: nil, state: .modified)
      }
      return ImageAssetStateResult(image: image, state: .available)
    } catch {
      return ImageAssetStateResult(image: nil, state: .permissionDenied)
    }
  }

  private func loadVerifiedLocalImage(filename: String, imageHash: String?) -> ImageAssetStateResult {
    do {
      let fileURL = try Self.localImageDirectory().appendingPathComponent(filename, isDirectory: false)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return ImageAssetStateResult(image: nil, state: .deleted)
      }
      let imageData = try Data(contentsOf: fileURL)
      guard let image = UIImage(data: imageData)?.normalizedForProcessing() else {
        return ImageAssetStateResult(image: nil, state: .deleted)
      }
      if let storedHash = imageHash, Self.hash(image: image) != storedHash {
        return ImageAssetStateResult(image: nil, state: .modified)
      }
      return ImageAssetStateResult(image: image, state: .available)
    } catch {
      return ImageAssetStateResult(image: nil, state: .deleted)
    }
  }

  private func requestPhotoWriteAccess() async -> PHAuthorizationStatus {
    await Self.requestPhotoAuthorization(for: .addOnly)
  }

  private func requestPhotoReadAccess() async -> PHAuthorizationStatus {
    await Self.requestPhotoAuthorization(for: .readWrite)
  }

  private nonisolated static func requestPhotoAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
    await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
      PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
        continuation.resume(returning: status)
      }
    }
  }

  private nonisolated static func createPhotoAsset(with imageData: Data) async throws -> String {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      let creationState = PhotoAssetCreationState()
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: imageData, options: nil)
        creationState.placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
      } completionHandler: { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success, let placeholderIdentifier = creationState.placeholderIdentifier {
          continuation.resume(returning: placeholderIdentifier)
        } else {
          continuation.resume(throwing: ImageAssetError.imageLoadFailed)
        }
      }
    }
  }

  private nonisolated static func loadImageData(localIdentifier: String) async throws -> Data {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
    guard let asset = assets.firstObject else {
      throw ImageAssetError.assetNotFound
    }

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      let options = PHImageRequestOptions()
      options.deliveryMode = .highQualityFormat
      options.isNetworkAccessAllowed = false
      options.isSynchronous = false

      PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
        if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
          continuation.resume(throwing: ImageAssetError.imageLoadFailed)
          return
        }
        if let error = info?[PHImageErrorKey] as? Error {
          continuation.resume(throwing: error)
          return
        }
        guard let data else {
          continuation.resume(throwing: ImageAssetError.imageLoadFailed)
          return
        }
        continuation.resume(returning: data)
      }
    }
  }

  private nonisolated static func deletePhotoAssets(localIdentifiers: [String]) async throws {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
    guard assets.count > 0 else {
      return
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.deleteAssets(assets)
      } completionHandler: { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: ImageAssetError.deletionFailed)
        }
      }
    }
  }

  private nonisolated static func deleteLocalImage(filename: String) throws {
    let fileURL = try localImageDirectory().appendingPathComponent(filename, isDirectory: false)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }
    try FileManager.default.removeItem(at: fileURL)
  }

  private nonisolated static func localImageDirectory() throws -> URL {
    let applicationSupportDirectory = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = applicationSupportDirectory.appendingPathComponent("ProcessedImages", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private final class PhotoAssetCreationState: @unchecked Sendable {
    private let lock = NSLock()
    private var _placeholderIdentifier: String?

    var placeholderIdentifier: String? {
      get {
        lock.withLock { _placeholderIdentifier }
      }
      set {
        lock.withLock {
          _placeholderIdentifier = newValue
        }
      }
    }
  }

  static func hash(image: UIImage) -> String {
    let normalized = image.normalizedForProcessing()
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: normalized.size, format: format)
    let flattened = renderer.image { _ in
      UIColor.white.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: normalized.size)).fill()
      normalized.draw(in: CGRect(origin: .zero, size: normalized.size))
    }
    let data = flattened.pngData() ?? Data()
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

struct ImageProcessingService {
  private let context = CIContext()

  func correctPerspective(image: UIImage, corners: [CGPoint]) throws -> UIImage {
    guard corners.count == 4 else {
      throw ImageAssetError.correctionFailed
    }

    let normalized = image.normalizedForProcessing()
    guard let ciImage = CIImage(image: normalized),
          let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      throw ImageAssetError.correctionFailed
    }

    let width = ciImage.extent.width
    let height = ciImage.extent.height
    let topLeft = ciPoint(from: corners[0], width: width, height: height)
    let topRight = ciPoint(from: corners[1], width: width, height: height)
    let bottomRight = ciPoint(from: corners[2], width: width, height: height)
    let bottomLeft = ciPoint(from: corners[3], width: width, height: height)

    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
    filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

    guard let output = filter.outputImage,
          let cgImage = context.createCGImage(output, from: output.extent) else {
      throw ImageAssetError.correctionFailed
    }

    return UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
  }

  private func ciPoint(from normalizedPoint: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
    CGPoint(
      x: normalizedPoint.x.clamped(to: 0...1) * width,
      y: (1 - normalizedPoint.y.clamped(to: 0...1)) * height
    )
  }
}

extension UIImage {
  func normalizedForProcessing() -> UIImage {
    guard imageOrientation != .up else {
      return self
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { _ in
      draw(in: CGRect(origin: .zero, size: size))
    }
  }
}

extension CGFloat {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
