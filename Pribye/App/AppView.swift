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
        ), onAnalysisStarted: {
          selectedTab = .prints
        })
        .environment(router)
        .tabItem { tab.label }
        .tag(tab)
      }
    }
    .task {
      showsUnsupportedAIAlert = !AppleIntelligenceAvailability().isSupported
    }
    .alert("Apple Intelligenceが必要です", isPresented: $showsUnsupportedAIAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("プリバイの解析にはApple Intelligenceが必要です。対応端末では設定でApple Intelligenceをオンにしてから利用してください。")
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

  func withSheetDestinations(
    sheet destination: Binding<SheetDestination?>,
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
    }
  }
}
