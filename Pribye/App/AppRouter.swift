import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case tasks
  case prints
  case aiExperiment
  case settings

  var id: String { rawValue }

  @MainActor
  @ViewBuilder
  func makeContentView() -> some View {
    switch self {
    case .tasks:
      TaskListView()
    case .prints:
      PrintListView()
    case .aiExperiment:
      AIExperimentView()
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .tasks:
      Label("タスク", systemImage: "checklist")
    case .prints:
      Label("プリント", systemImage: "doc.text")
    case .aiExperiment:
      Label("AI実験", systemImage: "bubble.left.and.text.bubble.right")
    case .settings:
      Label("設定", systemImage: "gearshape")
    }
  }
}

enum Route: Hashable {
  case task(UUID)
  case document(UUID)
}

enum SheetDestination: Identifiable, Hashable {
  case capture
  case manualTask(documentID: UUID?)

  var id: String {
    switch self {
    case .capture:
      return "capture"
    case .manualTask:
      return "manualTask"
    }
  }
}

@MainActor
@Observable
final class RouterPath {
  var path: [Route] = []
  var presentedSheet: SheetDestination?

  func navigate(to route: Route) {
    path.append(route)
  }
}

@MainActor
@Observable
final class TabRouter {
  private var routers: [AppTab: RouterPath] = [:]

  func router(for tab: AppTab) -> RouterPath {
    if let router = routers[tab] {
      return router
    }
    let router = RouterPath()
    routers[tab] = router
    return router
  }

  func binding(for tab: AppTab) -> Binding<[Route]> {
    let router = router(for: tab)
    return Binding(
      get: { router.path },
      set: { router.path = $0 }
    )
  }

  func replacePath(for tab: AppTab, with path: [Route]) {
    router(for: tab).path = path
  }
}
