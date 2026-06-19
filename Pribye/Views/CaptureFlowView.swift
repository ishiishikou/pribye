import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum CaptureStep {
  case input
  case correction
  case analyzing
  case review
  case failed(String)
}

struct CaptureFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("showReviewAfterAnalysis") private var showReviewAfterAnalysis = true

  @State private var step: CaptureStep = .input
  @State private var selectedItem: PhotosPickerItem?
  @State private var selectedImage: UIImage?
  @State private var cropCorners = CropPreview.defaultCorners
  @State private var isShowingCamera = false
  @State private var createdDocument: DocumentRecord?

  private let ocrService: OCRServiceProtocol = VisionOCRService()
  private let analyzer: DocumentAnalyzer = FoundationModelsDocumentAnalyzer()
  private let imageAssetService = ImageAssetService()
  private let imageProcessingService = ImageProcessingService()

  var body: some View {
    Group {
      switch step {
      case .input:
        inputView
      case .correction:
        correctionView
      case .analyzing:
        analyzingView
      case .review:
        if let createdDocument {
          AnalysisReviewView(document: createdDocument) {
            dismiss()
          }
        } else {
          ContentUnavailableView("解析結果がありません", systemImage: "doc.text.magnifyingglass")
        }
      case .failed(let message):
        failureView(message: message)
      }
    }
    .navigationTitle("撮影")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("キャンセル") { dismiss() }
      }
    }
    .onChange(of: selectedItem) { _, newValue in
      Task { await load(item: newValue) }
    }
    .fullScreenCover(isPresented: $isShowingCamera) {
      CameraImagePicker { image in
        selectedImage = image
        selectedItem = nil
        cropCorners = CropPreview.defaultCorners
        step = .correction
        isShowingCamera = false
      } onCancel: {
        isShowingCamera = false
      }
      .ignoresSafeArea()
    }
  }

  private var inputView: some View {
    VStack(spacing: 24) {
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 56))
        .foregroundStyle(.blue)

      Text("プリントを取り込む")
        .font(.title2.weight(.bold))

      Button {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          isShowingCamera = true
        } else {
          step = .failed("この端末ではカメラを利用できません")
        }
      } label: {
        Label("カメラで撮影", systemImage: "camera")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)

      PhotosPicker(selection: $selectedItem, matching: .images) {
        Label("写真から選ぶ", systemImage: "photo.on.rectangle")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)

      Button {
        SampleDataFactory.insertDemoDocument(into: modelContext)
        dismiss()
      } label: {
        Label("デモプリントを追加", systemImage: "sparkles")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)

      Text("写真・OCR・AI結果は外部AI APIへ送信しません。補正後の画像は写真ライブラリに保存します。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
  }

  private var correctionView: some View {
    VStack(spacing: 16) {
      if let selectedImage {
        CropPreview(image: selectedImage, corners: $cropCorners)
          .frame(maxHeight: 520)
      }

      Button {
        Task { await analyzeSelectedImage() }
      } label: {
        Label("解析へ進む", systemImage: "wand.and.stars")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }

  private var analyzingView: some View {
    VStack(spacing: 18) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 56))
        .foregroundStyle(.blue)
      Text("解析中です...")
        .font(.title3.weight(.semibold))
      VStack(alignment: .leading, spacing: 10) {
        Label("OCR処理中", systemImage: "checkmark")
        Label("AI解析中", systemImage: "checkmark")
        Label("タスクを作成中", systemImage: "checkmark")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func failureView(message: String) -> some View {
    VStack(spacing: 18) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 56))
        .foregroundStyle(.red)
      Text("このプリントから予定・持ち物を見つけられませんでした")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button("再解析する") {
        Task { await analyzeSelectedImage() }
      }
      .buttonStyle(.borderedProminent)
      Button("手動で登録する") {
        if let document = createdDocument {
          document.status = .ready
        }
        dismiss()
      }
    }
    .padding()
  }

  @MainActor
  private func load(item: PhotosPickerItem?) async {
    guard let item else {
      return
    }
    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
      step = .failed("画像を読み込めませんでした")
      return
    }
    let normalized = image.normalizedForProcessing()
    selectedImage = normalized
    cropCorners = CropPreview.defaultCorners
    step = .correction
  }

  @MainActor
  private func analyzeSelectedImage() async {
    guard let selectedImage else {
      step = .failed("画像が選択されていません")
      return
    }

    step = .analyzing
    let originalImage = selectedImage.normalizedForProcessing()
    let correctedImage: UIImage
    do {
      correctedImage = try imageProcessingService.correctPerspective(image: originalImage, corners: cropCorners)
    } catch {
      step = .failed("画像補正に失敗しました")
      return
    }

    let document = DocumentRecord(status: .ocrProcessing)
    document.thumbnailData = correctedImage.jpegData(compressionQuality: 0.45)
    modelContext.insert(document)
    createdDocument = document

    do {
      let savedAsset = try await imageAssetService.saveImage(correctedImage)
      document.photoAssetIdentifier = savedAsset.localIdentifier
      document.imageHash = savedAsset.imageHash

      let ocr = try await ocrService.recognizeText(in: correctedImage)
      let page = PageRecord(pageIndex: 0, ocrText: ocr.text)
      page.photoAssetIdentifier = document.photoAssetIdentifier
      page.imageHash = document.imageHash
      page.setCropCorners(cropCorners)
      page.observations = ocr.observations.map {
        OCRObservationRecord(
          text: $0.text,
          confidence: $0.confidence,
          boundingBoxX: $0.boundingBox.origin.x,
          boundingBoxY: $0.boundingBox.origin.y,
          boundingBoxWidth: $0.boundingBox.width,
          boundingBoxHeight: $0.boundingBox.height
        )
      }
      document.pages.append(page)
      document.ocrText = ocr.text
      document.status = .aiProcessing

      let snapshots = [
        OCRPageSnapshot(
          pageIndex: 0,
          text: ocr.text,
          observations: page.observations.map { OCRObservationSnapshot(id: $0.id, text: $0.text) }
        )
      ]
      let result = try await analyzer.analyze(pages: snapshots)
      document.title = result.documentTitle
      document.tasks = result.tasks.map { draft in
        let task = ExtractedTaskRecord(
          title: draft.title,
          note: draft.note,
          dueStart: draft.dueStart,
          dueEnd: draft.dueEnd,
          evidenceText: draft.evidenceText
        )
        task.evidenceObservationID = draft.evidenceObservationID
        return task
      }
      document.status = .ready

      if showReviewAfterAnalysis {
        step = .review
      } else {
        dismiss()
      }
    } catch DocumentAnalyzerError.noActionableTasks {
      document.status = .failed
      document.failureReason = .extractionError
      step = .failed("プリントの内容が確認しにくい可能性があります")
    } catch ImageAssetError.photoAccessDenied {
      document.status = .failed
      document.failureReason = .imageError
      step = .failed("補正後の画像を写真ライブラリへ保存できませんでした")
    } catch {
      document.status = .failed
      document.failureReason = .unknownError
      step = .failed("解析中にエラーが発生しました")
    }
  }
}

struct CropPreview: View {
  static let defaultCorners = [
    CGPoint(x: 0.06, y: 0.06),
    CGPoint(x: 0.94, y: 0.06),
    CGPoint(x: 0.94, y: 0.94),
    CGPoint(x: 0.06, y: 0.94)
  ]

  var image: UIImage
  @Binding var corners: [CGPoint]
  @State private var selectedCornerIndex = 0

  var body: some View {
    VStack(spacing: 12) {
      MagnifiedCornerView(image: image, corner: corners[selectedCornerIndex])
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      EditableCornerImage(image: image, corners: $corners, selectedCornerIndex: $selectedCornerIndex)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      Text("四隅を合わせてから解析へ進みます。上部で選択中の角を拡大確認できます。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

struct EditableCornerImage: View {
  var image: UIImage
  @Binding var corners: [CGPoint]
  @Binding var selectedCornerIndex: Int

  var body: some View {
    GeometryReader { proxy in
      let imageRect = fittedImageRect(in: proxy.size, imageSize: image.size)

      ZStack {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: proxy.size.width, height: proxy.size.height)

        Path { path in
          let displayPoints = corners.map { displayPoint(for: $0, in: imageRect) }
          path.addLines(displayPoints)
          path.closeSubpath()
        }
        .stroke(.blue, lineWidth: 2)

        ForEach(corners.indices, id: \.self) { index in
          let point = displayPoint(for: corners[index], in: imageRect)
          Circle()
            .fill(index == selectedCornerIndex ? .orange : .blue)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .position(point)
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  selectedCornerIndex = index
                  corners[index] = normalizedPoint(for: value.location, in: imageRect)
                }
            )
        }
      }
    }
    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
  }
}

struct MagnifiedCornerView: View {
  var image: UIImage
  var corner: CGPoint

  var body: some View {
    GeometryReader { proxy in
      let imageRect = fittedImageRect(in: proxy.size, imageSize: image.size)
      let displayCorner = displayPoint(for: corner, in: imageRect)

      ZStack {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .scaleEffect(2.6, anchor: UnitPoint(x: corner.x, y: corner.y))
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()
          .overlay {
            Circle()
              .stroke(.orange, lineWidth: 2)
              .frame(width: 30, height: 30)
              .position(displayCorner)
          }
      }
      .background(.secondary.opacity(0.08))
    }
  }
}

private func fittedImageRect(in container: CGSize, imageSize: CGSize) -> CGRect {
  guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
    return CGRect(origin: .zero, size: container)
  }

  let scale = min(container.width / imageSize.width, container.height / imageSize.height)
  let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  return CGRect(
    x: (container.width - size.width) / 2,
    y: (container.height - size.height) / 2,
    width: size.width,
    height: size.height
  )
}

private func displayPoint(for normalizedPoint: CGPoint, in rect: CGRect) -> CGPoint {
  CGPoint(
    x: rect.minX + normalizedPoint.x.clamped(to: 0...1) * rect.width,
    y: rect.minY + normalizedPoint.y.clamped(to: 0...1) * rect.height
  )
}

private func normalizedPoint(for displayPoint: CGPoint, in rect: CGRect) -> CGPoint {
  CGPoint(
    x: ((displayPoint.x - rect.minX) / max(rect.width, 1)).clamped(to: 0...1),
    y: ((displayPoint.y - rect.minY) / max(rect.height, 1)).clamped(to: 0...1)
  )
}

struct AnalysisReviewView: View {
  @Bindable var document: DocumentRecord
  var onSave: () -> Void

  var body: some View {
    List {
      Section("抽出されたタスク") {
        ForEach(document.tasks) { task in
          TaskRowView(task: task)
        }
        Button {
          let task = ExtractedTaskRecord(title: "新しいタスク")
          document.tasks.append(task)
        } label: {
          Label("手動で追加", systemImage: "plus")
        }
      }

      Section("プリント名") {
        TextField("プリント名", text: $document.title)
      }

      Section {
        Button("保存する", action: onSave)
          .buttonStyle(.borderedProminent)
      }
    }
    .navigationTitle("結果を確認")
    .navigationBarTitleDisplayMode(.inline)
  }
}
