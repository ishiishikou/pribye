# 実装メモ

## 設計矛盾の扱い

- 「解析中に画面を離れてよい」は、解析開始後に撮影シートを閉じてプリント一覧へ戻ることで扱う。解析結果確認画面は設けない。
- 「ローカル処理」と「広告」は、プリント画像・OCR・タスク内容を広告SDKへ渡さないことで境界を引く。広告通信自体はApp Storeのプライバシー申告対象として扱う。
- 「写真ライブラリのみ」と「根拠ハイライト」は、アプリ内にサムネイル・ページごとの画像参照・画像ハッシュ・OCR座標を保存する。カメラ/書類スキャン由来は補正後画像Photos asset、アルバム選択由来はアプリ内部保存ファイルを参照する。
- 「複数ページ撮影」と「長文によるAI精度低下防止」は、1プリントに複数 `Page` を持たせ、タスク抽出を対象ページ + 次ページ冒頭の文脈でページ単位実行することで両立する。
- 「Apple Intelligence対応端末のみ」は、iOS 26以上をdeployment targetにし、AI可用性は `AppleIntelligenceAvailability` で集約する。Apple Intelligence専用の配布制限キーは未確認のため、Info.plistへ推測追加しない。

## Foundation Models

`DocumentAnalyzer` はプロトコルで分離済み。`FoundationModelsDocumentAnalyzer` はFoundation Models接続の唯一の境界です。

`canImport(FoundationModels)` かつ `SystemLanguageModel.default.isAvailable` の場合は `LanguageModelSession` の自由応答を短いプロンプトで段階実行する。SDK未解決、Apple Intelligence利用不可、モデル未準備、モデル出力不正の場合はフォールバックせず、Apple Intelligenceをオンにする案内または解析失敗として扱う。

複数ページプリントでは、全ページを一括でタスク抽出へ渡さない。ページごとに対象ページを先頭にし、次ページ冒頭のOCR行だけを文脈として付ける。

実機またはGitHub ActionsのXcode 26環境でコンパイルと実機動作を確認する。確認手順は `docs/FOUNDATION_MODELS_SETUP.md` を参照する。

## Ads

広告SDKは Google Mobile Ads SDK（AdMob）を採用する。現在は公式テスト App ID / banner ad unit ID を `project.yml` の build setting に置いているため、App Store提出前に `docs/ADMOB_SETUP.md` に沿って本番IDへ差し替える。

## クラウドビルド

ローカルにMac/Xcodeがない前提で、GitHub Actionsが以下を行う。

1. Xcode 26系を選択する。
2. XcodeGenをインストールする。
3. `project.yml` から `Pribye.xcodeproj` を生成する。
4. 利用可能なiPhone Simulatorを選び、`xcodebuild test` を実行する。
