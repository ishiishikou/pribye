import Foundation
import SwiftData
import SwiftUI

@main
struct PribyeApp: App {
  init() {
    try? FileManager.default.createDirectory(
      at: URL.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
  }

  var body: some Scene {
    WindowGroup {
      AppView()
    }
    .modelContainer(for: [
      DocumentRecord.self,
      PageRecord.self,
      OCRObservationRecord.self,
      ExtractedTaskRecord.self
    ])
  }
}
