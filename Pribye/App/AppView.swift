import SwiftData
import SwiftUI

struct AppView: View {
  @State private var selectedTab: AppTab = .tasks
  @State private var tabRouter = TabRouter()
  @State private var showsUnsupportedAIAlert = false

  var body: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        let router = tabRouter.router(for: tab)
        NavigationStack(path: tabRouter.binding(for: tab)) {
          tab.makeContentView()
            .withAppRoutes()
        }
        .withSheetDestinations(sheet: Binding(
          get: { router.presentedSheet },
          set: { router.presentedSheet = $0 }
        ))
        .environment(router)
        .tabItem { tab.label }
        .tag(tab)
      }
    }
    .task {
      showsUnsupportedAIAlert = !AppleIntelligenceAvailability().isSupported
    }
    .alert("この端末ではAI解析を利用できません", isPresented: $showsUnsupportedAIAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("プリバイはiOS 26以降のApple Intelligence対応端末を対象にしています。")
    }
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

  func withSheetDestinations(sheet: Binding<SheetDestination?>) -> some View {
    sheet(item: sheet) { destination in
      NavigationStack {
        switch destination {
        case .capture:
          CaptureFlowView()
        case .manualTask(let documentID):
          ManualTaskView(documentID: documentID)
        }
      }
    }
  }
}
