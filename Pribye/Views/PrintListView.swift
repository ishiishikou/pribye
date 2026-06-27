import SwiftData
import SwiftUI

struct PrintListView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(RouterPath.self) private var router: RouterPath?
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]
  @State private var documentPendingDeletion: DocumentRecord?
  @State private var deleteErrorMessage: String?

  private let imageAssetService = ImageAssetService()

  var body: some View {
    Group {
      if documents.isEmpty {
        EmptyStateView(
          title: "プリントはありません",
          systemImage: "doc.text.image",
          actionTitle: "プリントを撮影"
        ) {
          router?.presentedSheet = .capture
        }
      } else {
        List {
          Section {
            ForEach(documents) { document in
              Button {
                router?.navigate(to: .document(document.id))
              } label: {
                DocumentRowView(document: document)
              }
              .buttonStyle(.plain)
              .swipeActions {
                Button("削除", role: .destructive) {
                  documentPendingDeletion = document
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("プリント")
    .safeAreaInset(edge: .bottom) {
      AdBannerPlaceholder()
        .background(.background)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          router?.presentedSheet = .capture
        } label: {
          Image(systemName: "camera")
        }
        .accessibilityLabel("プリントを撮影")
      }
    }
    .confirmationDialog(
      "プリントを削除しますか？",
      isPresented: Binding(
        get: { documentPendingDeletion != nil },
        set: { if !$0 { documentPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("プリントだけ削除", role: .destructive) {
        deletePendingDocument(deleteImages: false)
      }
      Button("プリントと保存画像を削除", role: .destructive) {
        deletePendingDocument(deleteImages: true)
      }
      Button("キャンセル", role: .cancel) {
        documentPendingDeletion = nil
      }
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

  private func deletePendingDocument(deleteImages: Bool) {
    guard let document = documentPendingDeletion else {
      return
    }
    documentPendingDeletion = nil

    Task { @MainActor in
      do {
        if deleteImages {
          try await imageAssetService.deleteStoredImages(for: document)
        }
        modelContext.delete(document)
      } catch {
        deleteErrorMessage = "写真アクセス権限または画像削除処理を確認してください。"
      }
    }
  }
}

struct DocumentRowView: View {
  var document: DocumentRecord

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "doc.text")
        .foregroundStyle(.indigo)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 4) {
        Text(document.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
        Text("\(document.capturedAt.formatted(.dateTime.year().month().day())) ・ \(document.tasks.count)件")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      HStack(spacing: 6) {
        if document.status.isProcessing {
          ProgressView()
            .controlSize(.small)
        }
        StatusPill(
          text: document.status.userLabel,
          color: document.status == .failed ? .red : .blue
        )
      }
    }
    .padding(.vertical, 6)
  }
}
