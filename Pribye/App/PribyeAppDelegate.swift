import UIKit

@MainActor
final class PribyeAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    GemmaModelDownloadManager.shared.setBackgroundCompletionHandler(
      completionHandler,
      for: identifier
    )
  }

  func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    Task {
      await GemmaEnginePool.shared.releaseForMemoryWarning()
    }
  }
}
