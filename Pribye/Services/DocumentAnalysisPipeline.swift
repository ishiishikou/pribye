import Foundation

struct DocumentAnalysisPipeline {
  var analyzer: DocumentAnalyzer = FoundationModelsDocumentAnalyzer()
  var ocrCorrector: OCRTextCorrector = FoundationModelsOCRTextCorrector()

  @MainActor
  func applyAnalysis(to document: DocumentRecord, snapshots: [OCRPageSnapshot]) async throws {
    let result = try await analyzePageScoped(snapshots)
    let correctedTasks = try await correctTaskEvidence(result.tasks, in: snapshots)

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
    document.failureReason = nil
    document.status = .ready
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

  private func correctTaskEvidence(_ tasks: [TaskDraft], in snapshots: [OCRPageSnapshot]) async throws -> [TaskDraft] {
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

      let correctedSnapshots = try await ocrCorrector.correct(pages: contextSnapshots)
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
}

func ocrSnapshots(from document: DocumentRecord) -> [OCRPageSnapshot] {
  document.pages
    .sorted { $0.pageIndex < $1.pageIndex }
    .map { page in
      OCRPageSnapshot(
        pageIndex: page.pageIndex,
        text: page.ocrText,
        observations: page.observations.map {
          OCRObservationSnapshot(id: $0.id, text: $0.text)
        }
      )
    }
}
