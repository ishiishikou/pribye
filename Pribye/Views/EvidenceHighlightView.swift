import SwiftData
import SwiftUI
import UIKit

struct EvidenceHighlightView: View {
  @Bindable var document: DocumentRecord
  var task: ExtractedTaskRecord

  @State private var sourceImage: UIImage?
  @State private var sourceState: SourceImageState = .available
  @State private var isLoading = true

  private let imageAssetService = ImageAssetService()

  var body: some View {
    Group {
      if isLoading {
        ProgressView("元画像を確認中")
      } else if let sourceImage, sourceState == .available {
        EvidenceImageCanvas(image: sourceImage, observations: highlightedObservations)
          .padding()
      } else {
        ContentUnavailableView(
          sourceState.message.isEmpty ? "元画像を表示できません" : sourceState.message,
          systemImage: "photo.badge.exclamationmark"
        )
      }
    }
    .navigationTitle("根拠ハイライト")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadImage()
    }
  }

  private var highlightedObservations: [OCRObservationRecord] {
    let observations = highlightedPage?.observations ?? document.pages.flatMap(\.observations)
    if let evidenceObservationID = task.evidenceObservationID,
       let observation = observations.first(where: { $0.id == evidenceObservationID }) {
      return [observation]
    }
    guard !task.evidenceText.isEmpty else {
      return []
    }
    return observations.filter {
      task.evidenceText.contains($0.text) || $0.text.contains(task.evidenceText)
    }
  }

  private var highlightedPage: PageRecord? {
    if let evidenceObservationID = task.evidenceObservationID {
      return document.pages.first { page in
        page.observations.contains { $0.id == evidenceObservationID }
      }
    }
    guard !task.evidenceText.isEmpty else {
      return nil
    }
    return document.pages.first { page in
      page.observations.contains {
        task.evidenceText.contains($0.text) || $0.text.contains(task.evidenceText)
      }
    }
  }

  @MainActor
  private func loadImage() async {
    isLoading = true
    defer { isLoading = false }

    let result: ImageAssetStateResult
    if let highlightedPage {
      result = await imageAssetService.loadVerifiedImage(for: highlightedPage)
    } else {
      result = await imageAssetService.loadVerifiedImage(for: document)
    }
    sourceImage = result.image
    sourceState = result.state
    document.sourceImageState = result.state
  }
}

struct EvidenceImageCanvas: View {
  var image: UIImage
  var observations: [OCRObservationRecord]

  var body: some View {
    GeometryReader { proxy in
      let imageRect = fittedEvidenceImageRect(in: proxy.size, imageSize: image.size)

      ZStack {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: proxy.size.width, height: proxy.size.height)

        ForEach(observations) { observation in
          let rect = displayRect(for: observation, in: imageRect)
          RoundedRectangle(cornerRadius: 3)
            .fill(.yellow.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.orange, lineWidth: 2))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
      }
    }
  }
}

private func fittedEvidenceImageRect(in container: CGSize, imageSize: CGSize) -> CGRect {
  guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
    return CGRect(origin: .zero, size: container)
  }

  let scale = Swift.min(container.width / imageSize.width, container.height / imageSize.height)
  let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  return CGRect(
    x: (container.width - size.width) / 2,
    y: (container.height - size.height) / 2,
    width: size.width,
    height: size.height
  )
}

private func displayRect(for observation: OCRObservationRecord, in imageRect: CGRect) -> CGRect {
  let x = imageRect.minX + CGFloat(observation.boundingBoxX) * imageRect.width
  let y = imageRect.minY + CGFloat(1 - observation.boundingBoxY - observation.boundingBoxHeight) * imageRect.height
  return CGRect(
    x: x,
    y: y,
    width: CGFloat(observation.boundingBoxWidth) * imageRect.width,
    height: CGFloat(observation.boundingBoxHeight) * imageRect.height
  )
}
