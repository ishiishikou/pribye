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
}

struct SavedImageAsset: Sendable {
  var localIdentifier: String
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
    let identifier = try await withCheckedThrowingContinuation { continuation in
      var placeholderIdentifier: String?
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: imageData, options: nil)
        placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
      } completionHandler: { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success, let placeholderIdentifier {
          continuation.resume(returning: placeholderIdentifier)
        } else {
          continuation.resume(throwing: ImageAssetError.imageLoadFailed)
        }
      }
    }

    return SavedImageAsset(localIdentifier: identifier, imageHash: hash)
  }

  func loadVerifiedImage(for document: DocumentRecord) async -> ImageAssetStateResult {
    guard let identifier = document.photoAssetIdentifier else {
      return ImageAssetStateResult(image: nil, state: .deleted)
    }

    let status = await requestPhotoReadAccess()
    guard status == .authorized || status == .limited else {
      return ImageAssetStateResult(image: nil, state: .permissionDenied)
    }

    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
    guard let asset = assets.firstObject else {
      return ImageAssetStateResult(image: nil, state: .deleted)
    }

    do {
      let image = try await loadImage(from: asset)
      if let storedHash = document.imageHash, Self.hash(image: image) != storedHash {
        return ImageAssetStateResult(image: nil, state: .modified)
      }
      return ImageAssetStateResult(image: image, state: .available)
    } catch {
      return ImageAssetStateResult(image: nil, state: .permissionDenied)
    }
  }

  private func requestPhotoWriteAccess() async -> PHAuthorizationStatus {
    await withCheckedContinuation { continuation in
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        continuation.resume(returning: status)
      }
    }
  }

  private func requestPhotoReadAccess() async -> PHAuthorizationStatus {
    await withCheckedContinuation { continuation in
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        continuation.resume(returning: status)
      }
    }
  }

  private func loadImage(from asset: PHAsset) async throws -> UIImage {
    try await withCheckedThrowingContinuation { continuation in
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
        guard let data, let image = UIImage(data: data) else {
          continuation.resume(throwing: ImageAssetError.imageLoadFailed)
          return
        }
        continuation.resume(returning: image.normalizedForProcessing())
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
    min(max(self, range.lowerBound), range.upperBound)
  }
}
