# 実装メモ

## 設計矛盾の扱い

- 「確認を毎回必須にしない」と「AI結果確認画面」は、設定 `showReviewAfterAnalysis` で両立する。初期値は確認画面を開くが、ユーザーが不要と判断したら解析後に自動保存へ切り替えられる。
- 「ローカル処理」と「広告」は、プリント画像・OCR・タスク内容を広告SDKへ渡さないことで境界を引く。広告通信自体はApp Storeのプライバシー申告対象として扱う。
- 「写真ライブラリのみ」と「根拠ハイライト」は、アプリ内にサムネイル・画像ハッシュ・OCR座標だけを保存し、補正後画像のPhotos assetが消えた場合はハイライト不可にする。
- 「Apple Intelligence対応端末のみ」は、iOS 26以上をdeployment targetにし、AI可用性は `AppleIntelligenceAvailability` で集約する。

## Foundation Models

`DocumentAnalyzer` はプロトコルで分離済み。`FoundationModelsDocumentAnalyzer` はFoundation Models接続の唯一の境界です。

`canImport(FoundationModels)` かつ `SystemLanguageModel.default.isAvailable` の場合は `LanguageModelSession` のstructured generationを使う。SDK未解決、Apple Intelligence利用不可、モデル未準備の場合は、CIとWindows編集環境で安全に動かすため `HeuristicDocumentAnalyzer` にフォールバックする。

実機またはGitHub ActionsのXcode 26環境でコンパイルと実機動作を確認する。確認手順は `docs/FOUNDATION_MODELS_SETUP.md` を参照する。

## Ads

広告SDKは Google Mobile Ads SDK（AdMob）を採用する。現在は公式テスト App ID / banner ad unit ID を `project.yml` の build setting に置いているため、App Store提出前に `docs/ADMOB_SETUP.md` に沿って本番IDへ差し替える。

## クラウドビルド

ローカルにMac/Xcodeがない前提で、GitHub Actionsが以下を行う。

1. Xcode 26系を選択する。
2. XcodeGenをインストールする。
3. `project.yml` から `Pribye.xcodeproj` を生成する。
4. 利用可能なiPhone Simulatorを選び、`xcodebuild test` を実行する。
