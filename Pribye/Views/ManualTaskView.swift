import SwiftData
import SwiftUI

struct ManualTaskView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var documentID: UUID?
  @Query private var documents: [DocumentRecord]

  @State private var title = ""
  @State private var note = ""
  @State private var dueDate: Date?
  @State private var hasDueDate = false

  var body: some View {
    Form {
      Section {
        TextField("タスク名", text: $title)
        TextField("メモ", text: $note, axis: .vertical)
        Toggle("期限を設定", isOn: $hasDueDate)
        if hasDueDate {
          DatePicker(
            "期限",
            selection: Binding(
              get: { dueDate ?? .now },
              set: { dueDate = $0 }
            ),
            displayedComponents: .date
          )
        }
      }

      Section {
        Button("保存") {
          save()
        }
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .navigationTitle("手動登録")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func save() {
    let task = ExtractedTaskRecord(
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      note: note,
      dueStart: hasDueDate ? dueDate ?? .now : nil
    )

    if let documentID, let document = documents.first(where: { $0.id == documentID }) {
      document.tasks.append(task)
    } else {
      let document = DocumentRecord(title: "手動登録", status: .ready)
      document.tasks.append(task)
      modelContext.insert(document)
    }

    dismiss()
  }
}
