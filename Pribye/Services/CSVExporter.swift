import Foundation

struct CSVExporter {
  func export(documents: [DocumentRecord]) -> String {
    let rows = documents.flatMap { document in
      document.tasks.map { task in
        [
          document.id.uuidString,
          document.title,
          document.status.userLabel,
          task.id.uuidString,
          task.title,
          format(task.dueStart),
          format(task.dueEnd),
          task.isCompleted ? "完了" : "未完了",
          task.evidenceText,
          document.ocrText.prefix(80).description
        ]
      }
    }

    let header = ["document_id", "document_title", "document_status", "task_id", "task_title", "due_start", "due_end", "task_status", "evidence", "ocr_summary"]
    return ([header] + rows)
      .map { $0.map(escape).joined(separator: ",") }
      .joined(separator: "\n")
  }

  private func format(_ date: Date?) -> String {
    guard let date else {
      return ""
    }
    return ISO8601DateFormatter().string(from: date)
  }

  private func escape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}
