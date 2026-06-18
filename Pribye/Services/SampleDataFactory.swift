import Foundation
import SwiftData

@MainActor
enum SampleDataFactory {
  static func insertDemoDocument(into context: ModelContext) {
    let document = DocumentRecord(title: "体操授業のお知らせ", status: .ready)
    document.ocrText = "6月20日までに体操服を持参してください。\n体育の授業で使用します。"

    let page = PageRecord(pageIndex: 0, ocrText: document.ocrText)
    let observation = OCRObservationRecord(
      text: "6月20日までに体操服を持参してください。",
      confidence: 0.94,
      boundingBoxX: 0.12,
      boundingBoxY: 0.52,
      boundingBoxWidth: 0.72,
      boundingBoxHeight: 0.05
    )
    page.observations.append(observation)
    document.pages.append(page)

    let due = DateRangeParser().parse("6月20日まで").start
    let task = ExtractedTaskRecord(
      title: "体操服を持参",
      dueStart: due,
      evidenceText: observation.text
    )
    task.evidenceObservationID = observation.id
    document.tasks.append(task)

    context.insert(document)
  }
}
