import SwiftData
import SwiftUI

@main
struct PribyeApp: App {
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
