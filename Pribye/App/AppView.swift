import SwiftData
import SwiftUI

struct AppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: AppTab = .tasks
  @State private var tabRouter = TabRouter()
  @State private var analysisNotifications = AnalysisNotificationStore()

  var body: some View {
    ZStack(alignment: .top) {
      TabView(selection: $selectedTab) {
        ForEach(AppTab.allCases) { tab in
          let router = tabRouter.router(for: tab)
        NavigationStack(path: tabRouter.binding(for: tab)) {
          tab.makeContentView()
            .withAppRoutes()
        }
        .environment(router)
        .environment(analysisNotifications)
        .withSheetDestinations(sheet: Binding(
          get: { router.presentedSheet },
          set: { router.presentedSheet = $0 }
        ), router: router, analysisNotifications: analysisNotifications, onAnalysisStarted: {
          selectedTab = .prints
        })
          .tabItem { tab.label }
          .tag(tab)
        }
      }

      if let notification = analysisNotifications.foregroundNotification {
        AnalysisCompletionBanner(notification: notification) {
          route(to: notification)
          analysisNotifications.clear(notification)
        } onDismiss: {
          analysisNotifications.clear(notification)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(1)
      }
    }
    .task {
      analysisNotifications.updateScenePhase(scenePhase)
      routePendingNotificationTaps()
    }
    .onChange(of: scenePhase) { _, newValue in
      analysisNotifications.updateScenePhase(newValue)
    }
    .onReceive(NotificationCenter.default.publisher(for: .analysisNotificationTapped)) { _ in
      routePendingNotificationTaps()
    }
  }

  private func route(to notification: AnalysisCompletionNotification) {
    selectedTab = notification.destinationTab
    if notification.outcome == .failure {
      tabRouter.replacePath(for: .prints, with: [.document(notification.documentID)])
    }
  }

  private func routePendingNotificationTaps() {
    for notification in AnalysisNotificationTapInbox.shared.drain() {
      route(to: notification)
    }
  }
}

private struct AnalysisCompletionBanner: View {
  var notification: AnalysisCompletionNotification
  var onTap: () -> Void
  var onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: notification.outcome == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(notification.outcome == .success ? .green : .orange)

      Text(notification.message)
        .font(.subheadline.weight(.semibold))

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("通知を閉じる")
    }
    .padding(12)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(radius: 6, y: 2)
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
  }
}

extension View {
  func withAppRoutes() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .task(let id):
        TaskDetailLookupView(taskID: id)
      case .document(let id):
        DocumentDetailLookupView(documentID: id)
      }
    }
  }

  func withSheetDestinations(
    sheet destination: Binding<SheetDestination?>,
    router: RouterPath,
    analysisNotifications: AnalysisNotificationStore,
    onAnalysisStarted: @escaping () -> Void
  ) -> some View {
    self.sheet(item: destination) { destination in
      NavigationStack {
        switch destination {
        case .capture:
          CaptureFlowView(onAnalysisStarted: onAnalysisStarted)
        case .manualTask(let documentID):
          ManualTaskView(documentID: documentID)
        }
      }
      .environment(router)
      .environment(analysisNotifications)
    }
  }
}
