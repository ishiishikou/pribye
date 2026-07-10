import SwiftData
import SwiftUI
import UIKit

struct TaskDetailLookupView: View {
  var taskID: UUID
  @Query private var tasks: [ExtractedTaskRecord]

  var body: some View {
    if let task = tasks.first(where: { $0.id == taskID }) {
      TaskDetailView(task: task)
    } else {
      ContentUnavailableView("タスクが見つかりません", systemImage: "exclamationmark.circle")
    }
  }
}

struct TaskDetailView: View {
  @Bindable var task: ExtractedTaskRecord
  @State private var calendarMessage: String?
  @State private var isRegisteringCalendar = false
  @State private var evidenceDocument: DocumentRecord?
  private let calendarService: CalendarServiceProtocol = EventKitCalendarService()

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            TextField("タスク", text: $task.title)
              .font(.title2.weight(.bold))
            StatusPill(text: task.isCompleted ? "完了" : "未完了", color: task.isCompleted ? .green : .blue)
          }

          DueDateText(start: task.dueStart, end: task.dueEnd)
            .font(.headline)

          TextField("メモ", text: $task.note, axis: .vertical)
            .lineLimit(3...6)
        }
        .padding(.vertical, 8)
      }

      Section("このタスクの根拠") {
        if task.evidenceText.isEmpty {
          Text("根拠テキストはありません")
            .foregroundStyle(.secondary)
        } else {
          Text(task.evidenceText)
          if task.evidenceObservationID == nil {
            Text("根拠の位置情報がないため、ハイライトを表示できません")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Button("ハイライトを表示") {
              evidenceDocument = task.document
            }
              .disabled(task.document?.sourceImageState != .available)
          }
        }
      }

      if let document = task.document, document.sourceImageState != .available {
        Section {
          Text(document.sourceImageState.message)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button(task.isCompleted ? "未完了に戻す" : "完了にする") {
          task.setCompleted(!task.isCompleted)
        }
        .buttonStyle(.borderedProminent)

        Button {
          Task { await registerCalendar() }
        } label: {
          if isRegisteringCalendar {
            ProgressView()
          } else {
            Label("カレンダーに登録", systemImage: "calendar.badge.plus")
          }
        }
        .disabled(!task.hasCalendarDate || isRegisteringCalendar)
      }

      if let calendarMessage {
        Section {
          Text(calendarMessage)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("タスク詳細")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $evidenceDocument) { document in
      NavigationStack {
        EvidenceHighlightView(document: document, task: task)
      }
    }
  }

  private func registerCalendar() async {
    isRegisteringCalendar = true
    defer { isRegisteringCalendar = false }

    do {
      task.calendarEventIdentifier = try await calendarService.register(task: task)
      calendarMessage = "カレンダーに登録しました"
    } catch {
      calendarMessage = (error as? LocalizedError)?.errorDescription ?? "カレンダー登録できませんでした"
    }
  }
}

struct DocumentDetailLookupView: View {
  var documentID: UUID
  @Query private var documents: [DocumentRecord]

  var body: some View {
    if let document = documents.first(where: { $0.id == documentID }) {
      DocumentDetailView(document: document)
    } else {
      ContentUnavailableView("プリントが見つかりません", systemImage: "doc.text")
    }
  }
}

struct DocumentDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(RouterPath.self) private var router: RouterPath?
  @Environment(AnalysisNotificationStore.self) private var analysisNotifications: AnalysisNotificationStore?
  @Bindable var document: DocumentRecord
  @State private var isReanalyzing = false
  @State private var isShowingDeleteConfirmation = false
  @State private var deleteErrorMessage: String?

  private let analysisPipeline = DocumentAnalysisPipeline()
  private let imageAssetService = ImageAssetService()

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          TextField("プリント名", text: $document.title)
            .font(.title2.weight(.bold))
          Text(document.capturedAt.formatted(.dateTime.year().month().day()))
            .font(.caption)
            .foregroundStyle(.secondary)
          StatusPill(text: document.status.userLabel, color: document.status == .failed ? .red : .blue)
          if let failureReason = document.failureReason {
            Text(failureReason.message)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 8)
      }

      Section("抽出されたタスク") {
        if document.tasks.isEmpty {
          Text(emptyTaskMessage)
            .foregroundStyle(.secondary)
          if document.status != .failed {
            Button("手動でタスクを追加") {
              router?.presentedSheet = .manualTask(documentID: document.id)
            }
          }
        } else {
          ForEach(document.tasks) { task in
            Button {
              router?.navigate(to: .task(task.id))
            } label: {
              TaskRowView(task: task)
            }
            .buttonStyle(.plain)
          }
        }
      }

      Section("元画像") {
        if let data = document.thumbnailData, let image = UIImage(data: data) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          Label("サムネイルはありません", systemImage: "photo")
            .foregroundStyle(.secondary)
        }

        if document.sourceImageState != .available {
          Text(document.sourceImageState.message)
            .foregroundStyle(.secondary)
        }
      }

      Section("OCR") {
        if document.ocrText.isEmpty {
          Text("OCR結果はありません")
            .foregroundStyle(.secondary)
        } else if !document.pages.isEmpty {
          ForEach(document.pages.sorted { $0.pageIndex < $1.pageIndex }) { page in
            VStack(alignment: .leading, spacing: 6) {
              Text("ページ\(page.pageIndex + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Text(page.ocrText)
                .font(.callout)
            }
            .padding(.vertical, 4)
          }
        } else {
          Text(document.ocrText)
            .font(.callout)
        }
      }

      if document.status == .failed {
        Section {
          Button {
            Task { await reanalyzeDocument() }
          } label: {
            if isReanalyzing {
              ProgressView()
            } else {
              Label("再解析する", systemImage: "arrow.clockwise")
            }
          }
          .disabled(isReanalyzing)
          Button("手動で登録する") {
            router?.presentedSheet = .manualTask(documentID: document.id)
          }
        }
      }
    }
    .navigationTitle("プリント詳細")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(role: .destructive) {
          isShowingDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityLabel("プリントを削除")
      }
    }
    .confirmationDialog(
      "プリントを削除しますか？",
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("プリントだけ削除", role: .destructive) {
        Task { await deleteDocument(deleteImages: false) }
      }
      Button("プリントと保存画像を削除", role: .destructive) {
        Task { await deleteDocument(deleteImages: true) }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("保存画像を削除すると、写真ライブラリやアプリ内部に保存した補正後画像も削除します。")
    }
    .alert("削除できませんでした", isPresented: Binding(
      get: { deleteErrorMessage != nil },
      set: { if !$0 { deleteErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(deleteErrorMessage ?? "")
    }
  }

  @MainActor
  private func reanalyzeDocument() async {
    let snapshots = ocrSnapshots(from: document)
    guard !snapshots.isEmpty else {
      document.status = .failed
      document.failureReason = .ocrError
      return
    }

    isReanalyzing = true
    defer { isReanalyzing = false }
    await analysisNotifications?.requestAuthorizationIfNeeded()

    let oldTasks = document.tasks
    document.tasks.removeAll()
    for task in oldTasks {
      modelContext.delete(task)
    }

    document.status = .aiProcessing
    document.failureReason = nil

    do {
      try await analysisPipeline.applyAnalysis(to: document, snapshots: snapshots)
      await deliverAnalysisCompletion(outcome: .success)
    } catch DocumentAnalyzerError.noActionableTasks {
      document.status = .failed
      document.failureReason = .extractionError
      await deliverAnalysisCompletion(outcome: .failure)
    } catch DocumentAnalyzerError.unsupportedDevice {
      document.status = .failed
      document.failureReason = .unsupportedDevice
      await deliverAnalysisCompletion(outcome: .failure)
    } catch DocumentAnalyzerError.modelNotReady {
      document.status = .failed
      document.failureReason = .modelNotReady
      await deliverAnalysisCompletion(outcome: .failure)
    } catch DocumentAnalyzerError.modelLoadFailed {
      document.status = .failed
      document.failureReason = .modelLoadFailed
      await deliverAnalysisCompletion(outcome: .failure)
    } catch DocumentAnalyzerError.malformedModelOutput {
      document.status = .failed
      document.failureReason = .extractionError
      await deliverAnalysisCompletion(outcome: .failure)
    } catch {
      document.status = .failed
      document.failureReason = .unknownError
      await deliverAnalysisCompletion(outcome: .failure)
    }
  }

  @MainActor
  private func deliverAnalysisCompletion(outcome: AnalysisNotificationOutcome) async {
    guard let analysisNotifications else {
      return
    }
    await analysisNotifications.deliver(
      AnalysisCompletionNotification(documentID: document.id, outcome: outcome)
    )
  }

  @MainActor
  private func deleteDocument(deleteImages: Bool) async {
    do {
      if deleteImages {
        try await imageAssetService.deleteStoredImages(for: document)
      }
      modelContext.delete(document)
      dismiss()
    } catch {
      deleteErrorMessage = "写真アクセス権限または画像削除処理を確認してください。"
    }
  }

  private var emptyTaskMessage: String {
    switch document.status {
    case .captured, .ocrProcessing, .aiProcessing:
      return "解析が完了すると、抽出されたタスクがここに表示されます。"
    case .failed:
      return "解析に失敗したため、タスクは作成されていません。"
    case .ready:
      return "このプリントから登録が必要なタスクは見つかりませんでした。"
    }
  }
}
