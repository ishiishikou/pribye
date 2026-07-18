import SwiftData
import SwiftUI

struct SettingsView: View {
  @Query(sort: \DocumentRecord.capturedAt, order: .reverse) private var documents: [DocumentRecord]

  @AppStorage("adsRemoved") private var adsRemoved = false
  @AppStorage("developmentSummaryPrompt") private var developmentSummaryPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
  @StateObject private var purchaseService = PurchaseService()
  @StateObject private var gemmaDownloadManager = GemmaModelDownloadManager.shared
  @State private var showDownloadConfirmation = false
  @State private var showCancelDownloadConfirmation = false
  @State private var showDeleteModelConfirmation = false
  @State private var allowsCellularDownload = false

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

        Text("解析にはGemma 4 E4Bのローカルモデルを使います。モデルはアプリに含めず、このiPhone内に保存します。")
          .font(.footnote)
          .foregroundStyle(.secondary)

        switch gemmaDownloadManager.state.phase {
        case .downloading:
          gemmaDownloadProgressView
        case .verifying:
          HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
              Text("モデルを検証中")
              Text("ダウンロードしたファイルの整合性を確認しています。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        case .idle, .failed:
          if gemmaDownloadManager.modelStatus == .ready {
            LabeledContent("使用容量", value: modelFileSizeText)
            LabeledContent("保存場所", value: "このiPhone内")
          } else {
            Button {
              showDownloadConfirmation = true
            } label: {
              Label(
                gemmaDownloadManager.modelStatus == .invalid ? "再ダウンロード" : "モデルをダウンロード",
                systemImage: "arrow.down.circle"
              )
            }
          }
        }

        if !gemmaDownloadManager.state.isActive,
           gemmaDownloadManager.modelStatus != .notDownloaded {
          Button(role: .destructive) {
            showDeleteModelConfirmation = true
          } label: {
            Label("モデルを削除", systemImage: "trash")
          }
        }

        if let message = gemmaDownloadManager.statusMessage {
          Text(message)
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
      gemmaDownloadManager.refreshModelStatus()
      if developmentSummaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        developmentSummaryPrompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
      }
      await purchaseService.loadRemoveAdsProduct()
      adsRemoved = await purchaseService.refreshEntitlement()
      for await isRemoved in purchaseService.updatedRemoveAdsEntitlements() {
        adsRemoved = isRemoved
      }
    }
    .sheet(isPresented: $showDownloadConfirmation) {
      downloadConfirmationSheet
    }
    .alert("ダウンロードを中止しますか？", isPresented: $showCancelDownloadConfirmation) {
      Button("中止する", role: .destructive) {
        gemmaDownloadManager.cancelDownload()
      }
      Button("続ける", role: .cancel) {}
    } message: {
      Text("途中まで受信したデータは削除されます。再度利用する場合は最初からダウンロードします。")
    }
    .alert("AIモデルを削除しますか？", isPresented: $showDeleteModelConfirmation) {
      Button("削除", role: .destructive) {
        gemmaDownloadManager.deleteModelAndDownloadData()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("端末の空き容量が増えます。AI解析を再び利用するには、モデルの再ダウンロードが必要です。")
    }
  }

  private var gemmaDownloadProgressView: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let progress = gemmaDownloadManager.state.progress {
        ProgressView(value: progress)
        HStack {
          Text(progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.headline.monospacedDigit())
          Spacer()
          Text("\(formattedBytes(gemmaDownloadManager.state.bytesDownloaded)) / \(formattedBytes(gemmaDownloadManager.state.totalBytes))")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      } else {
        ProgressView()
        Text(formattedBytes(gemmaDownloadManager.state.bytesDownloaded))
          .font(.footnote.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if gemmaDownloadManager.state.bytesPerSecond > 0 {
        HStack {
          Text("\(formattedSpeed(gemmaDownloadManager.state.bytesPerSecond))")
          Spacer()
          if let remaining = gemmaDownloadManager.state.estimatedTimeRemaining {
            Text("残り約\(formattedDuration(remaining))")
          }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
      }

      Label {
        Text("別の画面を開いたり、ホーム画面へ戻ったりしてもダウンロードは続きます。アプリを強制終了すると中断します。")
      } icon: {
        Image(systemName: "iphone.and.arrow.forward")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)

      Button(role: .destructive) {
        showCancelDownloadConfirmation = true
      } label: {
        Label("ダウンロードを中止", systemImage: "xmark.circle")
      }
    }
  }

  private var downloadConfirmationSheet: some View {
    NavigationStack {
      List {
        Section {
          Label("約3.66GBの空き容量を使用します", systemImage: "internaldrive")
          Label("この画面を閉じてもダウンロードを継続します", systemImage: "arrow.down.circle")
          Label("ダウンロード後は設定からいつでも削除できます", systemImage: "trash")
        }

        Section("通信設定") {
          Toggle("モバイル通信を許可", isOn: $allowsCellularDownload)
          Text(allowsCellularDownload
               ? "Wi-Fiが利用できない場合はモバイル通信を使用します。通信量に注意してください。"
               : "Wi-Fiに接続するまで待機し、モバイル通信は使用しません。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section {
          Text("ダウンロード中は別の画面やホーム画面へ移動して構いません。アプリを強制終了するとダウンロードは中断します。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("AIモデルをダウンロード")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            showDownloadConfirmation = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("開始") {
            showDownloadConfirmation = false
            gemmaDownloadManager.startDownload(
              allowsCellularAccess: allowsCellularDownload
            )
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var removeAdsButtonTitle: String {
    if let product = purchaseService.removeAdsProduct {
      return "広告を非表示にする（\(product.displayPrice)）"
    }
    return "広告を非表示にする"
  }

  private var gemmaModelStatusText: String {
    switch gemmaDownloadManager.state.phase {
    case .downloading:
      return "AIモデルをダウンロード中"
    case .verifying:
      return "AIモデルを検証中"
    case .failed:
      return "AIモデルの準備に失敗"
    case .idle:
      switch gemmaDownloadManager.modelStatus {
      case .notDownloaded:
        return "AIモデル未ダウンロード"
      case .ready:
        return "AIモデル準備完了"
      case .invalid:
        return "AIモデル検証失敗"
      }
    }
  }

  private var gemmaModelStatusIcon: String {
    switch gemmaDownloadManager.state.phase {
    case .downloading:
      return "arrow.down.circle.fill"
    case .verifying:
      return "checkmark.shield"
    case .failed:
      return "exclamationmark.triangle.fill"
    case .idle:
      switch gemmaDownloadManager.modelStatus {
      case .notDownloaded:
        return "icloud.and.arrow.down"
      case .ready:
        return "checkmark.circle.fill"
      case .invalid:
        return "exclamationmark.triangle.fill"
      }
    }
  }

  private var gemmaModelStatusColor: Color {
    switch gemmaDownloadManager.state.phase {
    case .downloading, .verifying:
      return .blue
    case .failed:
      return .orange
    case .idle:
      switch gemmaDownloadManager.modelStatus {
      case .notDownloaded:
        return .secondary
      case .ready:
        return .green
      case .invalid:
        return .orange
      }
    }
  }

  private var modelFileSizeText: String {
    formattedBytes(
      GemmaModelStore.shared.modelFileSize
        ?? GemmaModelStore.estimatedDownloadSizeBytes
    )
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
  }

  private func formattedSpeed(_ bytesPerSecond: Double) -> String {
    "\(formattedBytes(Int64(max(bytesPerSecond, 0))))/秒"
  }

  private func formattedDuration(_ duration: TimeInterval) -> String {
    let seconds = max(Int(duration.rounded()), 0)
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60

    if hours > 0 {
      return "\(hours)時間\(minutes)分"
    }
    if minutes > 0 {
      return "\(minutes)分\(remainingSeconds)秒"
    }
    return "\(remainingSeconds)秒"
  }
}
