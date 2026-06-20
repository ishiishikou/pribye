import SwiftData
import SwiftUI

struct SettingsView: View {
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]

  @AppStorage("adsRemoved") private var adsRemoved = false
  @AppStorage("developmentTaskExtractionPrompt") private var developmentTaskExtractionPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
  @StateObject private var purchaseService = PurchaseService()

  private var csvText: String {
    CSVExporter().export(documents: documents)
  }

  var body: some View {
    List {
      Section("広告") {
        if adsRemoved {
          Label("広告は非表示です", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Button {
            Task {
              if await purchaseService.purchaseRemoveAds() {
                adsRemoved = true
              }
            }
          } label: {
            if purchaseService.isLoading {
              ProgressView()
            } else {
              Label(removeAdsButtonTitle, systemImage: "cart")
            }
          }
          .disabled(purchaseService.isLoading)

          Button {
            Task {
              adsRemoved = await purchaseService.restoreRemoveAds()
            }
          } label: {
            Label("購入を復元", systemImage: "arrow.clockwise")
          }
          .disabled(purchaseService.isLoading)
        }

        if let statusMessage = purchaseService.statusMessage {
          Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        ShareLink(item: csvText) {
          Label("データのエクスポート（CSV）", systemImage: "square.and.arrow.up")
        }
      }

      Section("開発中") {
        Text("タスク抽出プロンプト")
          .font(.headline)
        Text("現在の本番解析に使われるプロンプトです。App Store提出前にこの開発用入力欄は削除してください。")
          .font(.footnote)
          .foregroundStyle(.secondary)
        TextEditor(text: $developmentTaskExtractionPrompt)
          .frame(minHeight: 180)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("既定プロンプトに戻す") {
          developmentTaskExtractionPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
        }
        .disabled(developmentTaskExtractionPrompt == FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions)
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
          Text(AppleIntelligenceAvailability().isSupported ? "この端末ではAI解析を利用できます" : "設定でApple Intelligenceをオンにしてから利用してください")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("設定")
    .task {
      if developmentTaskExtractionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        developmentTaskExtractionPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
      }
      await purchaseService.loadRemoveAdsProduct()
      adsRemoved = await purchaseService.refreshEntitlement()
      for await isRemoved in purchaseService.updatedRemoveAdsEntitlements() {
        adsRemoved = isRemoved
      }
    }
  }

  private var removeAdsButtonTitle: String {
    if let product = purchaseService.removeAdsProduct {
      return "広告を非表示にする（\(product.displayPrice)）"
    }
    return "広告を非表示にする"
  }
}
