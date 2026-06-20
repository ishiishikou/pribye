import SwiftData
import SwiftUI

struct PrintListView: View {
  @Environment(RouterPath.self) private var router
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]

  var body: some View {
    Group {
      if documents.isEmpty {
        EmptyStateView(
          title: "プリントはありません",
          systemImage: "doc.text.image",
          actionTitle: "プリントを撮影"
        ) {
          router.presentedSheet = .capture
        }
      } else {
        List {
          Section {
            ForEach(documents) { document in
              Button {
                router.navigate(to: .document(document.id))
              } label: {
                DocumentRowView(document: document)
              }
              .buttonStyle(.plain)
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
          router.presentedSheet = .capture
        } label: {
          Image(systemName: "camera")
        }
        .accessibilityLabel("プリントを撮影")
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
      StatusPill(
        text: document.status.userLabel,
        color: document.status == .failed ? .red : .blue
      )
    }
    .padding(.vertical, 6)
  }
}
