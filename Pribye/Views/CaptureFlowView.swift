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
  @State private var createdDocument: DocumentRecord?

  private let ocrService: OCRServiceProtocol = VisionOCRService()
  private let analyzer: DocumentAnalyzer = FoundationModelsDocumentAnalyzer()

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
  }

  private var inputView: some View {
    VStack(spacing: 24) {
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 56))
        .foregroundStyle(.blue)

      Text("プリントを取り込む")
        .font(.title2.weight(.bold))

      PhotosPicker(selection: $selectedItem, matching: .images) {
        Label("写真から選ぶ", systemImage: "photo.on.rectangle")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)

      Button {
        SampleDataFactory.insertDemoDocument(into: modelContext)
        dismiss()
      } label: {
        Label("デモプリントを追加", systemImage: "sparkles")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)

      Text("実機ではカメラ撮影からこの補正フローへ接続します。写真・OCR・AI結果は外部AI APIへ送信しません。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
  }

  private var correctionView: some View {
    VStack(spacing: 16) {
      if let selectedImage {
        CropPreview(image: selectedImage)
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

  private func load(item: PhotosPickerItem?) async {
    guard let item else {
      return
    }
    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
      step = .failed("画像を読み込めませんでした")
      return
    }
    selectedImage = image
    step = .correction
  }

  @MainActor
  private func analyzeSelectedImage() async {
    guard let selectedImage else {
      step = .failed("画像が選択されていません")
      return
    }

    step = .analyzing
    let document = DocumentRecord(status: .ocrProcessing)
    document.thumbnailData = selectedImage.jpegData(compressionQuality: 0.45)
    modelContext.insert(document)
    createdDocument = document

    do {
      let ocr = try await ocrService.recognizeText(in: selectedImage)
      let page = PageRecord(pageIndex: 0, ocrText: ocr.text)
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
    } catch {
      document.status = .failed
      document.failureReason = .unknownError
      step = .failed("解析中にエラーが発生しました")
    }
  }
}

struct CropPreview: View {
  var image: UIImage

  var body: some View {
    VStack(spacing: 12) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .overlay {
          GeometryReader { proxy in
            let points = [
              CGPoint(x: 18, y: 18),
              CGPoint(x: proxy.size.width - 18, y: 18),
              CGPoint(x: proxy.size.width - 18, y: proxy.size.height - 18),
              CGPoint(x: 18, y: proxy.size.height - 18)
            ]
            Path { path in
              path.addLines(points)
              path.closeSubpath()
            }
            .stroke(.blue, lineWidth: 2)

            ForEach(points.indices, id: \.self) { index in
              Circle()
                .fill(.blue)
                .frame(width: 14, height: 14)
                .position(points[index])
            }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))

      Text("上部で角を確認し、必要なら撮り直してください。初版では自動補正結果を保存します。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
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
