import SwiftData
import SwiftUI

struct TaskListView: View {
  @Environment(RouterPath.self) private var router: RouterPath?
  @Query(sort: \ExtractedTaskRecord.createdAt, order: .reverse) private var tasks: [ExtractedTaskRecord]
  @State private var showingCompleted = false

  private var visibleTasks: [ExtractedTaskRecord] {
    tasks
      .filter { showingCompleted ? $0.isCompleted : !$0.isCompleted }
      .sorted { lhs, rhs in
        (lhs.dueStart ?? lhs.dueEnd ?? .distantFuture) < (rhs.dueStart ?? rhs.dueEnd ?? .distantFuture)
      }
  }

  var body: some View {
    Group {
      if visibleTasks.isEmpty {
        EmptyStateView(
          title: showingCompleted ? "完了したタスクはありません" : "まだタスクはありません",
          systemImage: "checklist",
          actionTitle: "プリントを撮影"
        ) {
          router?.presentedSheet = .capture
        }
      } else {
        List {
          Section {
            Picker("表示", selection: $showingCompleted) {
              Text("未完了").tag(false)
              Text("完了済み").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
          }

          Section {
            ForEach(visibleTasks) { task in
              Button {
                router?.navigate(to: .task(task.id))
              } label: {
                TaskRowView(task: task)
              }
              .buttonStyle(.plain)
              .swipeActions {
                Button(task.isCompleted ? "未完了" : "完了") {
                  task.setCompleted(!task.isCompleted)
                }
                .tint(task.isCompleted ? .orange : .green)
              }
            }
          }
        }
      }
    }
    .navigationTitle("タスク")
    .safeAreaInset(edge: .bottom) {
      AdBannerPlaceholder()
        .background(.background)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          router?.presentedSheet = .capture
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("プリントを撮影")
      }
    }
  }
}

struct TaskRowView: View {
  @Bindable var task: ExtractedTaskRecord

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "doc.badge.clock")
        .foregroundStyle(task.isCompleted ? .green : .blue)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .strikethrough(task.isCompleted)
        DueDateText(start: task.dueStart, end: task.dueEnd)
          .font(.caption)
      }

      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 6)
  }
}
