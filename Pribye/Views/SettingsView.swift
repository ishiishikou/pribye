import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]

  @AppStorage("showReviewAfterAnalysis") private var showReviewAfterAnalysis = true
  @AppStorage("adsRemoved") private var adsRemoved = false

  private var csvText: String {
    CSVExporter().export(documents: documents)
  }

  var body: some View {
    List {
      Section {
        Toggle("解析後に確認画面を開く", isOn: $showReviewAfterAnalysis)
        Toggle("広告を非表示にする", isOn: $adsRemoved)
      }

      Section {
        ShareLink(item: csvText) {
          Label("データのエクスポート（CSV）", systemImage: "square.and.arrow.up")
        }
        Button {
          SampleDataFactory.insertDemoDocument(into: modelContext)
        } label: {
          Label("デモデータを追加", systemImage: "sparkles")
        }
      }

      Section("その他") {
        Label("使い方", systemImage: "questionmark.circle")
        Label("プライバシーについて", systemImage: "lock")
        Label("サポート", systemImage: "envelope")
        Label("バージョン情報", systemImage: "info.circle")
      }

      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("Apple Intelligence")
            .font(.headline)
          Text(AppleIntelligenceAvailability().isSupported ? "この端末ではAI解析を利用できます" : "この端末ではAI解析を利用できません")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("設定")
  }
}
