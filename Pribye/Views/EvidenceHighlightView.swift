import SwiftData
import SwiftUI
import UIKit

struct EvidenceHighlightView: View {
  @Bindable var document: DocumentRecord
  var task: ExtractedTaskRecord

  @State private var sourceImage: UIImage?
  @State private var sourceState: SourceImageState = .available
  @State private var isLoading = true
  @State private var unavailableMessage: String?

  private let imageAssetService = ImageAssetService()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      evidenceTextView

      Group {
        if isLoading {
          ProgressView("元画像を確認中")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let unavailableMessage {
          ContentUnavailableView(unavailableMessage, systemImage: "text.viewfinder")
        } else if let sourceImage, sourceState == .available {
          EvidenceImageCanvas(image: sourceImage, observations: highlightedObservations)
        } else {
          ContentUnavailableView(
            sourceState.message.isEmpty ? "元画像を表示できません" : sourceState.message,
            systemImage: "photo.badge.exclamationmark"
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding()
    .navigationTitle("根拠ハイライト")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadImage()
    }
  }

  private var evidenceTextView: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("このタスクの根拠")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if task.evidenceText.isEmpty {
        Text("根拠テキストはありません")
          .foregroundStyle(.secondary)
      } else {
        Text(task.evidenceText)
          .font(.callout)
          .lineLimit(6)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var highlightedObservations: [OCRObservationRecord] {
    guard let evidenceObservationID = task.evidenceObservationID,
          let observations = highlightedPage?.observations,
          let observation = observations.first(where: { $0.id == evidenceObservationID }) else {
      return []
    }
    return [observation]
  }

  private var highlightedPage: PageRecord? {
    guard let evidenceObservationID = task.evidenceObservationID else {
      return nil
    }
    return document.pages.first { page in
      page.observations.contains { $0.id == evidenceObservationID }
    }
  }

  private var missingHighlightMessage: String? {
    guard task.evidenceObservationID != nil else {
      return "根拠の位置情報がないため、ハイライトを表示できません"
    }
    guard highlightedPage != nil else {
      return "根拠に対応するページが見つからないため、ハイライトを表示できません"
    }
    guard !highlightedObservations.isEmpty else {
      return "根拠に対応する行が見つからないため、ハイライトを表示できません"
    }
    return nil
  }

  @MainActor
  private func loadImage() async {
    isLoading = true
    defer { isLoading = false }

    if let missingHighlightMessage {
      unavailableMessage = missingHighlightMessage
      sourceImage = nil
      return
    }

    guard let highlightedPage else {
      unavailableMessage = "根拠に対応するページが見つからないため、ハイライトを表示できません"
      sourceImage = nil
      return
    }

    unavailableMessage = nil
    let result = await imageAssetService.loadVerifiedImage(for: highlightedPage)
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
  let rect = CGRect(
    x: x,
    y: y,
    width: CGFloat(observation.boundingBoxWidth) * imageRect.width,
    height: CGFloat(observation.boundingBoxHeight) * imageRect.height
  )
  return paddedRect(rect, inside: imageRect)
}

private func paddedRect(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
  let padded = rect.insetBy(dx: -4, dy: -3)
  return padded.intersection(bounds)
}
