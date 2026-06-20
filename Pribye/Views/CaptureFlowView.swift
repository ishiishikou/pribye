import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import VisionKit

enum CaptureStep {
  case input
  case correction
  case analyzing
  case review
  case failed(String)
}

struct CapturedPageImage: Identifiable {
  let id = UUID()
  var image: UIImage
  var cropCorners: [CGPoint] = defaultCropCorners()
  var source: CapturedPageSource = .camera
}

enum CapturedPageSource {
  case camera
  case photoLibrary
  case documentScanner
}

struct CaptureFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("showReviewAfterAnalysis") private var showReviewAfterAnalysis = true

  @State private var step: CaptureStep = .input
  @State private var selectedItem: PhotosPickerItem?
  @State private var capturedPages: [CapturedPageImage] = []
  @State private var selectedPageIndex = 0
  @State private var isShowingDocumentScanner = false
  @State private var isShowingCamera = false
  @State private var createdDocument: DocumentRecord?

  private let ocrService: OCRServiceProtocol = VisionOCRService()
  private let ocrCorrector: OCRTextCorrector = FoundationModelsOCRTextCorrector()
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
    .fullScreenCover(isPresented: $isShowingDocumentScanner) {
      DocumentScannerView { images in
        useScannedImages(images)
        isShowingDocumentScanner = false
      } onCancel: {
        isShowingDocumentScanner = false
      } onError: { _ in
        isShowingDocumentScanner = false
        step = .failed("書類スキャンに失敗しました")
      }
      .ignoresSafeArea()
    }
      .fullScreenCover(isPresented: $isShowingCamera) {
      CameraImagePicker { image in
        setCapturedPages([image], source: .camera)
        selectedItem = nil
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
        if VNDocumentCameraViewController.isSupported {
          isShowingDocumentScanner = true
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
          isShowingCamera = true
        } else {
          step = .failed("この端末ではカメラを利用できません")
        }
      } label: {
        Label("書類をスキャン", systemImage: "doc.viewfinder")
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

      Text("写真・OCR・AI結果は外部AI APIへ送信しません。写真から選んだ画像は写真ライブラリへ再保存しません。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
  }

  private var correctionView: some View {
    VStack(spacing: 16) {
      if capturedPages.count > 1 {
        Picker("ページ", selection: $selectedPageIndex) {
          ForEach(capturedPages.indices, id: \.self) { index in
            Text("\(index + 1)").tag(index)
          }
        }
        .pickerStyle(.segmented)
      }

      if let selectedPage {
        Text("\(selectedPageIndex + 1) / \(capturedPages.count)ページ")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        CropPreview(
          image: selectedPage.image,
          corners: selectedPageCorners,
          instructionText: cropInstructionText(for: selectedPage)
        )
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
    setCapturedPages([image], source: .photoLibrary)
  }

  @MainActor
  private func useScannedImages(_ images: [UIImage]) {
    guard !images.isEmpty else {
      step = .failed("スキャン画像を読み込めませんでした")
      return
    }

    setCapturedPages(images, initialCropCorners: fullCropCorners(), source: .documentScanner)
    selectedItem = nil
  }

  @MainActor
  private func setCapturedPages(
    _ images: [UIImage],
    initialCropCorners: [CGPoint] = defaultCropCorners(),
    source: CapturedPageSource = .camera
  ) {
    capturedPages = images.map {
      CapturedPageImage(
        image: $0.normalizedForProcessing(),
        cropCorners: initialCropCorners,
        source: source
      )
    }
    selectedPageIndex = 0
    step = capturedPages.isEmpty ? .failed("画像を読み込めませんでした") : .correction
  }

  private var selectedPage: CapturedPageImage? {
    guard capturedPages.indices.contains(selectedPageIndex) else {
      return nil
    }
    return capturedPages[selectedPageIndex]
  }

  private var selectedPageCorners: Binding<[CGPoint]> {
    Binding(
      get: {
        guard capturedPages.indices.contains(selectedPageIndex) else {
          return CropPreview.defaultCorners
        }
        return capturedPages[selectedPageIndex].cropCorners
      },
      set: { newValue in
        guard capturedPages.indices.contains(selectedPageIndex) else {
          return
        }
        capturedPages[selectedPageIndex].cropCorners = newValue
      }
    )
  }

  @MainActor
  private func analyzeSelectedImage() async {
    guard !capturedPages.isEmpty else {
      step = .failed("画像が選択されていません")
      return
    }

    step = .analyzing
    let document = DocumentRecord(status: .ocrProcessing)
    modelContext.insert(document)
    createdDocument = document

    do {
      var rawSnapshots: [OCRPageSnapshot] = []

      for (pageIndex, capturedPage) in capturedPages.enumerated() {
        let correctedImage = try imageProcessingService.correctPerspective(
          image: capturedPage.image.normalizedForProcessing(),
          corners: capturedPage.cropCorners
        )

        if pageIndex == 0 {
          document.thumbnailData = correctedImage.jpegData(compressionQuality: 0.45)
        }

        let imageReference = try await saveImageReference(correctedImage, source: capturedPage.source)
        if pageIndex == 0 {
          document.photoAssetIdentifier = imageReference.photoAssetIdentifier
          document.localImageFilename = imageReference.localImageFilename
          document.imageHash = imageReference.imageHash
        }

        let ocr = try await ocrService.recognizeText(in: correctedImage)
        let page = PageRecord(pageIndex: pageIndex, ocrText: ocr.text)
        page.photoAssetIdentifier = imageReference.photoAssetIdentifier
        page.localImageFilename = imageReference.localImageFilename
        page.imageHash = imageReference.imageHash
        page.setCropCorners(capturedPage.cropCorners)
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
        rawSnapshots.append(
          OCRPageSnapshot(
            pageIndex: pageIndex,
            text: ocr.text,
            observations: page.observations.map { OCRObservationSnapshot(id: $0.id, text: $0.text) }
          )
        )
      }

      document.ocrText = combinedOCRText(from: rawSnapshots)
      document.status = .aiProcessing

      let result = try await analyzePageScoped(rawSnapshots)
      let correctedTasks = await correctTaskEvidence(result.tasks, in: rawSnapshots)
      document.title = result.documentTitle
      document.tasks = correctedTasks.map { draft in
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
    } catch ImageAssetError.imageLoadFailed {
      document.status = .failed
      document.failureReason = .imageError
      step = .failed("補正後の画像を保存できませんでした")
    } catch ImageAssetError.correctionFailed {
      document.status = .failed
      document.failureReason = .imageError
      step = .failed("画像補正に失敗しました")
    } catch {
      document.status = .failed
      document.failureReason = .unknownError
      step = .failed("解析中にエラーが発生しました")
    }
  }

  private func analyzePageScoped(_ snapshots: [OCRPageSnapshot]) async throws -> AnalysisResult {
    var documentTitle: String?
    var tasks: [TaskDraft] = []

    for index in snapshots.indices {
      let scopedSnapshots = pageScopedSnapshots(targetIndex: index, snapshots: snapshots)
      do {
        let result = try await analyzer.analyze(pages: scopedSnapshots)
        if documentTitle == nil, !result.documentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          documentTitle = result.documentTitle
        }

        let targetObservationIDs = Set(snapshots[index].observations.map(\.id))
        tasks.append(contentsOf: result.tasks.filter { draft in
          guard let evidenceObservationID = draft.evidenceObservationID else {
            return false
          }
          return targetObservationIDs.contains(evidenceObservationID)
        })
      } catch DocumentAnalyzerError.noActionableTasks {
        continue
      }
    }

    let uniqueTasks = deduplicatedTasks(tasks)
    guard !uniqueTasks.isEmpty else {
      throw DocumentAnalyzerError.noActionableTasks
    }

    return AnalysisResult(
      documentTitle: documentTitle ?? inferredDocumentTitle(from: snapshots),
      tasks: uniqueTasks
    )
  }

  private func saveImageReference(_ image: UIImage, source: CapturedPageSource) async throws -> StoredImageReference {
    switch source {
    case .photoLibrary:
      let savedFile = try imageAssetService.saveImageLocally(image)
      return StoredImageReference(
        photoAssetIdentifier: nil,
        localImageFilename: savedFile.filename,
        imageHash: savedFile.imageHash
      )
    case .camera, .documentScanner:
      let savedAsset = try await imageAssetService.saveImage(image)
      return StoredImageReference(
        photoAssetIdentifier: savedAsset.localIdentifier,
        localImageFilename: nil,
        imageHash: savedAsset.imageHash
      )
    }
  }

  private func correctTaskEvidence(_ tasks: [TaskDraft], in snapshots: [OCRPageSnapshot]) async -> [TaskDraft] {
    var correctedTasks = tasks
    var correctedEvidenceByObservationID: [UUID: String] = [:]

    for index in correctedTasks.indices {
      guard let evidenceObservationID = correctedTasks[index].evidenceObservationID else {
        continue
      }
      if let cachedText = correctedEvidenceByObservationID[evidenceObservationID] {
        correctedTasks[index].evidenceText = cachedText
        continue
      }
      guard let contextSnapshots = correctionContextSnapshots(
        for: evidenceObservationID,
        in: snapshots
      ) else {
        continue
      }

      let correctedSnapshots = await ocrCorrector.correct(pages: contextSnapshots)
      guard let correctedText = correctedSnapshots
        .flatMap(\.observations)
        .first(where: { $0.id == evidenceObservationID })?
        .text
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !correctedText.isEmpty
      else {
        continue
      }

      correctedEvidenceByObservationID[evidenceObservationID] = correctedText
      correctedTasks[index].evidenceText = correctedText
    }

    return correctedTasks
  }

  private func correctionContextSnapshots(for observationID: UUID, in snapshots: [OCRPageSnapshot]) -> [OCRPageSnapshot]? {
    let sortedSnapshots = snapshots.sorted { $0.pageIndex < $1.pageIndex }
    for pagePosition in sortedSnapshots.indices {
      let page = sortedSnapshots[pagePosition]
      guard let observationIndex = page.observations.firstIndex(where: { $0.id == observationID }) else {
        continue
      }

      var context: [OCRPageSnapshot] = []
      if observationIndex == page.observations.startIndex,
         pagePosition > sortedSnapshots.startIndex,
         let previousObservation = sortedSnapshots[pagePosition - 1].observations.last {
        context.append(
          OCRPageSnapshot(
            pageIndex: sortedSnapshots[pagePosition - 1].pageIndex,
            text: previousObservation.text,
            observations: [previousObservation]
          )
        )
      }

      let lowerBound = Swift.max(page.observations.startIndex, observationIndex - 1)
      let upperBound = Swift.min(page.observations.index(before: page.observations.endIndex), observationIndex + 1)
      let targetContext = Array(page.observations[lowerBound...upperBound])
      context.append(
        OCRPageSnapshot(
          pageIndex: page.pageIndex,
          text: targetContext.map(\.text).joined(separator: "\n"),
          observations: targetContext
        )
      )

      if observationIndex == page.observations.index(before: page.observations.endIndex),
         pagePosition < sortedSnapshots.index(before: sortedSnapshots.endIndex),
         let nextObservation = sortedSnapshots[pagePosition + 1].observations.first {
        context.append(
          OCRPageSnapshot(
            pageIndex: sortedSnapshots[pagePosition + 1].pageIndex,
            text: nextObservation.text,
            observations: [nextObservation]
          )
        )
      }

      return context
    }

    return nil
  }

  private func pageScopedSnapshots(targetIndex: Int, snapshots: [OCRPageSnapshot]) -> [OCRPageSnapshot] {
    guard snapshots.indices.contains(targetIndex) else {
      return []
    }

    var scopedSnapshots = [snapshots[targetIndex]]
    let nextIndex = targetIndex + 1
    if snapshots.indices.contains(nextIndex) {
      let nextPage = snapshots[nextIndex]
      let contextObservations = Array(nextPage.observations.prefix(3))
      if !contextObservations.isEmpty {
        scopedSnapshots.append(OCRPageSnapshot(
          pageIndex: nextPage.pageIndex,
          text: contextObservations.map(\.text).joined(separator: "\n"),
          observations: contextObservations
        ))
      }
    }
    return scopedSnapshots
  }

  private func combinedOCRText(from snapshots: [OCRPageSnapshot]) -> String {
    snapshots
      .sorted { $0.pageIndex < $1.pageIndex }
      .map { snapshot in
        if snapshots.count == 1 {
          return snapshot.text
        }
        return "ページ\(snapshot.pageIndex + 1)\n\(snapshot.text)"
      }
      .joined(separator: "\n\n")
  }

  private func deduplicatedTasks(_ tasks: [TaskDraft]) -> [TaskDraft] {
    var seenKeys: Set<String> = []
    var uniqueTasks: [TaskDraft] = []
    for task in tasks {
      let key = [
        task.title,
        task.evidenceObservationID?.uuidString ?? "",
        task.dueStart?.description ?? "",
        task.dueEnd?.description ?? ""
      ].joined(separator: "|")
      guard !seenKeys.contains(key) else {
        continue
      }
      seenKeys.insert(key)
      uniqueTasks.append(task)
    }
    return uniqueTasks
  }

  private func inferredDocumentTitle(from snapshots: [OCRPageSnapshot]) -> String {
    snapshots
      .flatMap { $0.text.components(separatedBy: .newlines) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "プリント"
  }

  private func cropInstructionText(for page: CapturedPageImage) -> String {
    switch page.source {
    case .documentScanner:
      return "この画面でも四隅を選んで調整できます。上部の拡大表示で、指に隠れる角を確認できます。"
    case .camera, .photoLibrary:
      return "四隅を合わせてから解析へ進みます。上部で選択中の角を拡大確認できます。"
    }
  }
}

private struct StoredImageReference {
  var photoAssetIdentifier: String?
  var localImageFilename: String?
  var imageHash: String
}

struct CropPreview: View {
  static let defaultCorners = defaultCropCorners()

  var image: UIImage
  @Binding var corners: [CGPoint]
  var instructionText: String
  @State private var selectedCornerIndex = 0

  var body: some View {
    VStack(spacing: 12) {
      MagnifiedCornerView(image: image, corners: corners, selectedCornerIndex: selectedCornerIndex)
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      EditableCornerImage(image: image, corners: $corners, selectedCornerIndex: $selectedCornerIndex)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      Text(instructionText)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

private func defaultCropCorners() -> [CGPoint] {
  [
    CGPoint(x: 0.06, y: 0.06),
    CGPoint(x: 0.94, y: 0.06),
    CGPoint(x: 0.94, y: 0.94),
    CGPoint(x: 0.06, y: 0.94)
  ]
}

private func fullCropCorners() -> [CGPoint] {
  [
    CGPoint(x: 0, y: 0),
    CGPoint(x: 1, y: 0),
    CGPoint(x: 1, y: 1),
    CGPoint(x: 0, y: 1)
  ]
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
    .aspectRatio(image.size.width / Swift.max(image.size.height, CGFloat(1)), contentMode: .fit)
  }
}

struct MagnifiedCornerView: View {
  var image: UIImage
  var corners: [CGPoint]
  var selectedCornerIndex: Int

  var body: some View {
    GeometryReader { proxy in
      if corners.indices.contains(selectedCornerIndex), corners.count >= 3 {
        let imageRect = fittedImageRect(in: proxy.size, imageSize: image.size)
        let selectedCorner = corners[selectedCornerIndex]

        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .overlay {
            let displayPoints = corners.map { displayPoint(for: $0, in: imageRect) }
            ZStack {
              Path { path in
                path.addLines(displayPoints)
                path.closeSubpath()
              }
              .stroke(.blue, lineWidth: 2)

              Path { path in
                let selectedPoint = displayPoints[selectedCornerIndex]
                let previousPoint = displayPoints[(selectedCornerIndex + displayPoints.count - 1) % displayPoints.count]
                let nextPoint = displayPoints[(selectedCornerIndex + 1) % displayPoints.count]
                path.move(to: previousPoint)
                path.addLine(to: selectedPoint)
                path.addLine(to: nextPoint)
              }
              .stroke(.orange, lineWidth: 4)

              ForEach(corners.indices, id: \.self) { index in
                Circle()
                  .fill(index == selectedCornerIndex ? .orange : .blue)
                  .frame(width: index == selectedCornerIndex ? 28 : 18, height: index == selectedCornerIndex ? 28 : 18)
                  .overlay(Circle().stroke(.white, lineWidth: 3))
                  .position(displayPoints[index])
              }
            }
          }
          .scaleEffect(2.6, anchor: UnitPoint(x: selectedCorner.x, y: selectedCorner.y))
          .clipped()
          .background(.secondary.opacity(0.08))
      }
    }
  }
}

private func fittedImageRect(in container: CGSize, imageSize: CGSize) -> CGRect {
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

private func displayPoint(for normalizedPoint: CGPoint, in rect: CGRect) -> CGPoint {
  CGPoint(
    x: rect.minX + normalizedPoint.x.clamped(to: 0...1) * rect.width,
    y: rect.minY + normalizedPoint.y.clamped(to: 0...1) * rect.height
  )
}

private func normalizedPoint(for displayPoint: CGPoint, in rect: CGRect) -> CGPoint {
  CGPoint(
    x: ((displayPoint.x - rect.minX) / Swift.max(rect.width, CGFloat(1))).clamped(to: 0...1),
    y: ((displayPoint.y - rect.minY) / Swift.max(rect.height, CGFloat(1))).clamped(to: 0...1)
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
