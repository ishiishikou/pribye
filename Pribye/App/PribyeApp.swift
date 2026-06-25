import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
import SwiftData
import SwiftUI
import UserNotifications

@main
struct PribyeApp: App {
  init() {
    try? FileManager.default.createDirectory(
      at: URL.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    #if canImport(GoogleMobileAds)
    MobileAds.shared.start()
    #endif
    UNUserNotificationCenter.current().delegate = AnalysisNotificationDelegate.shared
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
