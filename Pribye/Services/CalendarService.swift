import EventKit
import Foundation

enum CalendarRegistrationError: LocalizedError, Equatable {
  case missingDate
  case accessDenied
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .missingDate:
      return "期限がないタスクはカレンダー登録できません"
    case .accessDenied:
      return "カレンダー登録にはアクセス許可が必要です"
    case .saveFailed:
      return "カレンダー登録できませんでした"
    }
  }
}

@MainActor
protocol CalendarServiceProtocol {
  func register(task: ExtractedTaskRecord) async throws -> String
}

@MainActor
final class EventKitCalendarService: CalendarServiceProtocol {
  private let eventStore = EKEventStore()

  func register(task: ExtractedTaskRecord) async throws -> String {
    guard let start = task.dueStart ?? task.dueEnd else {
      throw CalendarRegistrationError.missingDate
    }

    let granted = try await requestAccess()
    guard granted else {
      throw CalendarRegistrationError.accessDenied
    }

    let event = EKEvent(eventStore: eventStore)
    event.title = task.title
    event.notes = task.note.isEmpty ? task.evidenceText : task.note
    event.calendar = eventStore.defaultCalendarForNewEvents
    event.isAllDay = true
    event.startDate = start

    if let end = task.dueEnd {
      event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
    } else {
      event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
    }

    do {
      try eventStore.save(event, span: .thisEvent)
      return event.eventIdentifier
    } catch {
      throw CalendarRegistrationError.saveFailed
    }
  }

  private func requestAccess() async throws -> Bool {
    if #available(iOS 17.0, *) {
      return try await eventStore.requestFullAccessToEvents()
    }
    return try await eventStore.requestAccess(to: .event)
  }
}
