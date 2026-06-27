import SwiftData
import SwiftUI

struct SettingsView: View {
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]

  @AppStorage("adsRemoved") private var adsRemoved = false
  @AppStorage("developmentSummaryPrompt") private var developmentSummaryPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
  @StateObject private var purchaseService = PurchaseService()
  @State private var gemmaModelStatus: GemmaModelStatus = .notDownloaded
  @State private var isDownloadingGemmaModel = false
  @State private var gemmaModelMessage: String?

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

      Section("AIモデル") {
        Label(gemmaModelStatusText, systemImage: gemmaModelStatusIcon)
          .foregroundStyle(gemmaModelStatusColor)

        Text("解析にはGemma 4 E4Bのローカルモデルを使います。モデルはアプリに含めず、初回利用前にダウンロードします。")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if isDownloadingGemmaModel {
          HStack {
            ProgressView()
            Text("ダウンロード中")
          }
        } else {
          Button {
            Task { await downloadGemmaModel() }
          } label: {
            Label(gemmaModelStatus == .invalid ? "再ダウンロード" : "モデルをダウンロード", systemImage: "arrow.down.circle")
          }
          .disabled(gemmaModelStatus == .ready)

          if gemmaModelStatus != .notDownloaded {
            Button(role: .destructive) {
              deleteGemmaModel()
            } label: {
              Label("モデルを削除", systemImage: "trash")
            }
          }
        }

        if let gemmaModelMessage {
          Text(gemmaModelMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section("開発中") {
        Text("要約プロンプト")
          .font(.headline)
        Text("本番解析の最初の要約ステップに使われるプロンプトです。App Store提出前にこの開発用入力欄は削除してください。")
          .font(.footnote)
          .foregroundStyle(.secondary)
        TextEditor(text: $developmentSummaryPrompt)
          .frame(minHeight: 80)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("既定プロンプトに戻す") {
          developmentSummaryPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
        }
        .disabled(developmentSummaryPrompt == FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions)
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
      refreshGemmaModelStatus()
      if developmentSummaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        developmentSummaryPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
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

  private var gemmaModelStatusText: String {
    switch gemmaModelStatus {
    case .notDownloaded:
      return "AIモデル未ダウンロード"
    case .ready:
      return "AIモデル準備完了"
    case .invalid:
      return "AIモデル検証失敗"
    }
  }

  private var gemmaModelStatusIcon: String {
    switch gemmaModelStatus {
    case .notDownloaded:
      return "icloud.and.arrow.down"
    case .ready:
      return "checkmark.circle.fill"
    case .invalid:
      return "exclamationmark.triangle.fill"
    }
  }

  private var gemmaModelStatusColor: Color {
    switch gemmaModelStatus {
    case .notDownloaded:
      return .secondary
    case .ready:
      return .green
    case .invalid:
      return .orange
    }
  }

  private func refreshGemmaModelStatus() {
    gemmaModelStatus = GemmaModelStore.shared.status()
  }

  @MainActor
  private func downloadGemmaModel() async {
    isDownloadingGemmaModel = true
    gemmaModelMessage = "約3.66GBのモデルをダウンロードします。完了後にハッシュ検証します。"
    do {
      try await GemmaModelStore.shared.downloadModel()
      refreshGemmaModelStatus()
      gemmaModelMessage = "モデルの準備が完了しました。"
    } catch {
      refreshGemmaModelStatus()
      gemmaModelMessage = "モデルのダウンロードまたは検証に失敗しました。"
    }
    isDownloadingGemmaModel = false
  }

  private func deleteGemmaModel() {
    do {
      try GemmaModelStore.shared.deleteModel()
      refreshGemmaModelStatus()
      gemmaModelMessage = "モデルを削除しました。"
    } catch {
      gemmaModelMessage = "モデルを削除できませんでした。"
    }
  }
}
