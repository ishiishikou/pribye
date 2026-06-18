# プリバイ 引き継ぎメモ

## 目的

このファイルは、新規セッションで `HANDOFF.md` を読むだけで、プリバイの現在地、完了済み作業、次に着手すべきこと、注意点が分かるようにするための引き継ぎ資料です。

## アプリ概要

**プリバイ（プリントばいばい）** は、学校・幼稚園などから配布される紙プリントを撮影し、必要な行動だけを抽出してタスク化するiPhoneアプリです。

思想としては「プリント管理アプリ」ではなく、紙に書かれた情報をユーザーの頭から外すためのアプリです。プリントは入力データであり、主役はタスクです。

## 入力資料

元の企画資料は `input` フォルダにあります。

- `input/仕様書.md`
- `input/UI設計.md`
- `input/画面案.png`
- `input/icon.png`

重要な前提:

- 個人利用が主目的。
- App Store公開を目指す。
- ユーザーはMacを持っていない。
- Windowsで編集し、iOSビルドはGitHub ActionsのmacOS runnerで行う。
- iOS 26+ / SwiftUI / SwiftData / Vision OCR / Apple Intelligence・Foundation Models前提。
- 外部AI APIへプリント画像、OCR全文、抽出タスク内容を送信しない。

## GitHub / CI 状態

Repository:

- `https://github.com/ishiishikou/pribye.git`
- default branch: `main`

GitHub Actions:

- workflow: `.github/workflows/ios.yml`
- `xcodegen generate` と `xcodebuild test` を macOS runner で実行
- workflow: `.github/workflows/testflight.yml`
- TestFlight upload用の手動実行workflow。`workflow_dispatch` のみで自動実行しない。
- 確認済みの成功run:
  - `27737585159` `Document TestFlight upload preparation`
  - `27737437580` `Mark Bundle ID registration complete`
  - `27737095844` `Configure Apple development team`
  - `27736637531` `Add required app bundle metadata`

注意:

- private repository の GitHub-hosted macOS runner は GitHub Actions の無料枠を消費する。
- `main` へのpushでCIが走るため、無料枠節約のため、次チャットでは必要なときだけpushする。
- ローカルcommitだけならGitHub Actionsは走らない。

## Apple Developer / App Store Connect 状態

完了済み:

- Apple Developer Program 承認済み。
- Team ID: `2QA6W85W3D`
- Bundle ID: `com.pribye.app`
- Apple Developer の explicit App ID `com.pribye.app` 登録済み。
- App Store Connect の New App 作成済み。
- App Store Connect 上の状態は「提出準備中」。
- App Store Connect API key 作成済み。
- Apple Distribution certificate 作成済み。
- App Store provisioning profile for `com.pribye.app` 作成済み。
- TestFlight upload 用の GitHub Actions repository secrets 登録済み。

注意:

- secrets の値、`.p8`、`.p12`、provisioning profile の中身はこのリポジトリに記録しない。

プロジェクト設定:

- `project.yml`
  - `DEVELOPMENT_TEAM: 2QA6W85W3D`
  - `PRODUCT_BUNDLE_IDENTIFIER: com.pribye.app`
  - `CODE_SIGN_STYLE: Automatic`
  - `MARKETING_VERSION: "1.0"`
  - `CURRENT_PROJECT_VERSION: "1"`

関連ドキュメント:

- `docs/APP_STORE_CHECKLIST.md`
- `docs/TESTFLIGHT_UPLOAD.md`

## 実装済み

### プロジェクト構成

- `project.yml`
  - XcodeGen用設定
  - iOS 26.0 deployment target
  - iPhone向け設定（`TARGETED_DEVICE_FAMILY: "1"`）
  - `Pribye` app target
  - `PribyeTests` unit test target
- `.github/workflows/ios.yml`
  - GitHub Actions macOS runnerで `xcodegen generate` と `xcodebuild test` を実行
- `.github/workflows/testflight.yml`
  - GitHub Actions macOS runnerで署名付きarchiveを作成し、TestFlightへuploadする手動実行workflow
  - `workflow_dispatch` のみで自動実行しない
- `.gitignore`
- `README.md`
- `docs/APP_STORE_CHECKLIST.md`
- `docs/TESTFLIGHT_UPLOAD.md`
- `Pribye/Resources/Info.plist`
- `Pribye/Resources/Assets.xcassets`
  - `input/icon.png` を元にAppIcon用のiPhone各サイズと1024px marketing iconを生成済み

### アプリ本体

主なファイル:

- `Pribye/App/PribyeApp.swift`
- `Pribye/App/AppView.swift`
- `Pribye/App/AppRouter.swift`
- `Pribye/Models/DocumentModels.swift`
- `Pribye/Services/DateRangeParser.swift`
- `Pribye/Services/DocumentAnalyzer.swift`
- `Pribye/Services/OCRService.swift`
- `Pribye/Services/CalendarService.swift`
- `Pribye/Services/CSVExporter.swift`
- `Pribye/Services/SampleDataFactory.swift`
- `Pribye/Views/TaskListView.swift`
- `Pribye/Views/PrintListView.swift`
- `Pribye/Views/DetailViews.swift`
- `Pribye/Views/CaptureFlowView.swift`
- `Pribye/Views/ManualTaskView.swift`
- `Pribye/Views/SettingsView.swift`
- `Pribye/Views/Components.swift`

### モデル

`Document -> Page -> OCRObservation -> ExtractedTask` を基本構造として実装済み。

- `DocumentRecord`
  - プリント単位
  - 処理状態、ライフサイクル、写真アセットID、画像ハッシュ、サムネイル、OCR全文を保持
- `PageRecord`
  - 複数ページ対応
  - OCRテキスト、四隅補正座標を保持
- `OCRObservationRecord`
  - OCR行、信頼度、座標を保持
- `ExtractedTaskRecord`
  - タスク名、期限/期間、完了状態、根拠テキスト、カレンダーイベントIDを保持

### UI

実装済みの画面:

- タスク一覧
- プリント一覧
- タスク詳細
- プリント詳細
- 撮影/補正/解析/結果確認フロー
- 手動タスク追加
- 設定

UI方針:

- `TabView` は `タスク / プリント / 設定`
- 撮影はシートで表示
- 広告は一覧画面下部のプレースホルダーのみ
- 撮影、補正、確認、詳細画面には広告を表示しない
- 解析後の確認画面は設定でON/OFF可能

### サービス

実装済み:

- `VisionOCRService`
  - Vision OCR用
- `DocumentAnalyzer`
  - AI抽出境界
- `FoundationModelsDocumentAnalyzer`
  - Foundation Models用アダプタ予定
  - 現在は `HeuristicDocumentAnalyzer` へフォールバック
- `HeuristicDocumentAnalyzer`
  - OCRテキストから期限/期間と行動らしい文を簡易抽出
- `DateRangeParser`
  - `6月20日まで`、`6/15〜6/20` などを解析
- `EventKitCalendarService`
  - ユーザー操作によるカレンダー登録
- `CSVExporter`
  - 設定画面からCSV共有

### テスト

追加済み:

- `PribyeTests/DateRangeParserTests.swift`
- `PribyeTests/DocumentAnalyzerTests.swift`
- `PribyeTests/ModelStateTests.swift`

対象:

- 日付/期間パース
- ヒューリスティックAI抽出
- タスク完了状態とライフサイクル
- Document状態表示

## 直近で解決した問題

CIを通すために以下を修正済み:

- GitHub Actions の Simulator destination 選択を安定化。
- Swift 6 で `AnalysisFailureReason` の `Error` 適合を定義元へ移動。
- SwiftUI の `sheet` modifier 名衝突を修正。
- `Info.plist` に必須 bundle metadata を追加。
- `project.yml` に version build settings を追加。
- `DEVELOPMENT_TEAM` を `2QA6W85W3D` に設定。
- TestFlight archive時に Apple Distribution 署名を明示。
- App Store Connect upload検証に必要な `CFBundleIconName`、iPhone orientation、iPhone AppIconサイズ、iPhone対象設定を追加。
- XcodeGenのresources指定を `Pribye/Resources` に変更し、`Assets.xcassets` がasset catalogとしてcompileされるように修正。
- `altool` がupload失敗ログを出してもstep成功扱いになるケースを防ぐため、uploadログ内の失敗文字列を検出してworkflowを失敗させるように修正。

## 現在の重要な制約

### Foundation Models

`FoundationModelsDocumentAnalyzer` はまだ実API接続していません。

理由:

- iOS 26 SDKとApple Intelligence対応実機での検証が必要。
- CI上でも扱える状態を優先し、現時点ではヒューリスティック抽出へフォールバックしている。

次の実装者は、Foundation Models公式APIを確認し、`FoundationModelsDocumentAnalyzer.analyze(pages:)` の内部だけを差し替えるのがよいです。

### カメラ・四隅補正

現在の撮影フローは `PhotosPicker` とデモデータ中心です。

未実装:

- 実機カメラ撮影
- 写真ライブラリへの原本保存
- `assetIdentifier` 保存
- 画像ハッシュ生成と変更検知
- 実際の四隅ドラッグ操作
- 四隅補正後の画像変換

UIとして補正画面の骨格はありますが、実補正処理はまだです。

### 広告・課金

広告と課金はプレースホルダーです。

実装済み:

- 一覧画面下部の広告プレースホルダー
- 設定画面の「広告を非表示にする」トグル

未実装:

- 広告SDK
- StoreKit課金
- App Store用のプライバシー申告内容確定

広告SDKを入れる場合も、プリント画像、OCR、タスク名、抽出内容を広告SDKへ渡さない方針を守る必要があります。

## 次にやること

優先度順:

1. ユーザー承認後にpushする。pushすると既存の `.github/workflows/ios.yml` が走り、macOS Actions無料枠を消費する。
2. `TestFlight Upload` workflowを手動実行し、App Store Connect uploadまで成功するか確認する。
3. TestFlightで実機確認する。
4. 実機カメラ撮影、写真保存、四隅補正、画像ハッシュ、根拠ハイライトを実装する。
5. Foundation Models実API接続を検証・実装する。
6. StoreKit課金と広告SDKの採否・実装を決める。

## 次チャットでの推奨依頼

```text
HANDOFF.md を読んで、プリバイ開発の現在地を把握してください。
pushはまだしないでください。GitHub Actions無料枠を節約したいので、必要な作業はまずローカルで止めてください。
TestFlight upload 用のGitHub Actions secretsは登録済みです。
次は、ユーザー承認後にpushし、`TestFlight Upload` workflowを手動実行してください。
```

## 注意

- `main` にpushするとGitHub Actionsが走る。無料枠節約のため、pushはユーザー確認後に行う。
- private repo の macOS Actions は無料枠を消費する。
- ローカルcommitだけならActionsは走らない。
- Macがない前提では、TestFlight upload はGitHub Actionsで行う想定。
- `input` フォルダと `Agent.md` は元資料・補助資料として残す。不要に削除しない。
- 細かい分類、優先度、場所、全文検索中心機能、クラウド同期、ユーザーアカウント、家族共有は現時点の設計対象外。勝手に追加しない。
