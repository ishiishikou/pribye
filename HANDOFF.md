# プリバイ 引き継ぎメモ

## 目的

このファイルは、新規セッションで `HANDOFF.md` を読むだけで、プリバイの開発経緯・現在の進捗・次に着手すべきことが分かるようにするための引き継ぎ資料です。

## アプリ概要

**プリバイ（プリントばいばい）** は、学校・幼稚園などから配布される紙プリントを撮影し、必要な行動だけを抽出してタスク化するiPhoneアプリです。

思想としては「プリント管理アプリ」ではなく、紙に書かれた情報をユーザーの頭から外すためのアプリです。プリントは入力データであり、主役はタスクです。

## 入力資料

元の企画資料は `input` フォルダにあります。

- `input/仕様書.md`
- `input/UI設計.md`
- `input/画面案.png`
- `input/icon.png`

仕様上の重要な前提:

- 個人利用が主目的。
- ただしApp Store公開を目指す。
- ユーザーはMacを持っていない。
- クラウドビルド前提。
- iOS 26+ / SwiftUI / SwiftData / Vision OCR / Apple Intelligence・Foundation Models前提。
- 外部AI APIへプリント画像、OCR全文、抽出タスク内容を送信しない。

## 設計判断

最初に設計矛盾を確認し、以下の方針で進めることにしました。

- 新規iOSアプリとして作成する。
- ローカルWindowsでは編集中心、ビルドはGitHub ActionsのmacOS runnerで行う。
- Xcodeプロジェクトは直接コミットせず、`project.yml` からXcodeGenで生成する。
- SwiftUI + SwiftDataで実装する。
- 端末対象はiOS 26+、Apple Intelligence対応端末のみ。
- Apple Intelligence非対応端末では起動時に「この端末ではAI解析を利用できません」と表示する。
- `DocumentAnalyzer` プロトコルを置き、Foundation Models実装をアプリ本体から分離する。
- Foundation Modelsの実API接続は実機/iOS 26環境で検証が必要なため、現時点ではCIでも動かせるヒューリスティック抽出にフォールバックしている。

## 実装済み

### プロジェクト構成

以下を追加済みです。

- `project.yml`
  - XcodeGen用設定
  - iOS 26.0 deployment target
  - `Pribye` app target
  - `PribyeTests` unit test target
- `.github/workflows/ios.yml`
  - GitHub Actions macOS runnerで `xcodegen generate` と `xcodebuild test` を実行
- `.gitignore`
- `README.md`
- `Pribye/Resources/Info.plist`
- `Pribye/Resources/Assets.xcassets`
  - `input/icon.png` をAppIconへコピー済み

### アプリ本体

追加済みの主なファイル:

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

`Document -> Page -> OCRObservation -> ExtractedTask` を基本構造として実装済みです。

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

テスト対象:

- 日付/期間パース
- ヒューリスティックAI抽出
- タスク完了状態とライフサイクル
- Document状態表示

## 確認済み

Windowsローカルで確認済み:

- `git diff --check` はOK
- Asset JSONのパースはOK

未確認:

- Swiftコンパイル
- XcodeGen生成
- iOS Simulatorでのビルド/テスト

理由:

- 現在のWindows環境には `swift` がない
- 現在のWindows環境には `xcodegen` がない
- 実際のiOSビルドはGitHub ActionsのmacOS runnerで確認する想定

## 現在の重要な制約

### Foundation Models

`FoundationModelsDocumentAnalyzer` はまだ実API接続していません。

理由:

- iOS 26 SDKとApple Intelligence対応実機での検証が必要
- CI上でも扱える状態を優先し、現時点ではヒューリスティック抽出へフォールバックしている

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

1. GitHubへpushしてActionsでビルド確認する。
2. `xcodegen generate` や `xcodebuild test` のCIエラーを修正する。
3. iOS 26 SDK/Xcode 26がGitHub Actions runnerで利用できるか確認する。
4. `FoundationModelsDocumentAnalyzer` に実際のFoundation Models API呼び出しを接続する。
5. 実機カメラ撮影を `CaptureFlowView` に接続する。
6. 写真ライブラリ保存、`assetIdentifier`、画像ハッシュ、原本削除/権限解除/変更検知を実装する。
7. 四隅ドラッグ補正と画像変換を実装する。
8. OCR座標から根拠ハイライト表示を実装する。
9. StoreKit課金と広告SDKの採否・実装を決める。
10. App Store公開前にApple Developer Program、Bundle ID、Signing、App Store Connect、TestFlight、Privacy Nutrition Labelを整備する。

## 新規セッションへの指示例

新しいチャットでは、まず以下のように依頼するとスムーズです。

```text
HANDOFF.md を読んで、プリバイ開発の現在地を把握してください。
次に GitHub Actions でビルドが通る状態にするため、project.yml とSwiftコードを点検し、必要なら修正してください。
```

または、Foundation Models接続から進めたい場合:

```text
HANDOFF.md を読んで、DocumentAnalyzer の設計を確認してください。
FoundationModelsDocumentAnalyzer にiOS 26のFoundation Models APIを接続する実装方針を確認し、必要なコード変更をしてください。
```

## 注意

このリポジトリには現在、元資料の `input` フォルダと `Agent.md` も未追跡ファイルとして存在しています。不要に削除しないでください。

既存の設計思想では、細かい分類、優先度、場所、全文検索中心機能、クラウド同期、ユーザーアカウント、家族共有は意図的に対象外です。実装時に勝手に追加しないでください。
