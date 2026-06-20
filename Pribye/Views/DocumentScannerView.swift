import SwiftUI
import UIKit
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
  var onScan: ([UIImage]) -> Void
  var onCancel: () -> Void
  var onError: (Error) -> Void

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = context.coordinator
    return scanner
  }

  func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onScan: onScan, onCancel: onCancel, onError: onError)
  }

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private let onScan: ([UIImage]) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    init(
      onScan: @escaping ([UIImage]) -> Void,
      onCancel: @escaping () -> Void,
      onError: @escaping (Error) -> Void
    ) {
      self.onScan = onScan
      self.onCancel = onCancel
      self.onError = onError
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      let images = (0..<scan.pageCount).map { pageIndex in
        scan.imageOfPage(at: pageIndex).normalizedForProcessing()
      }
      onScan(images)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onCancel()
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      onError(error)
    }
  }
}
