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
- TestFlight upload用workflow。`workflow_dispatch` の手動実行に加え、`iOS` workflowが`main`へのpushで成功した場合に自動実行する。
- 確認済みの成功run:
  - `27737585159` `Document TestFlight upload preparation`
  - `27737437580` `Mark Bundle ID registration complete`
  - `27737095844` `Configure Apple development team`
  - `27736637531` `Add required app bundle metadata`

注意:

- private repository の GitHub-hosted macOS runner は GitHub Actions の無料枠を消費する。
- `main` へのpushでiOS CIが走り、成功するとTestFlight Uploadも続けて走るため、無料枠節約のため、次チャットでは必要なときだけpushする。
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
- `docs/ADMOB_SETUP.md`
- `docs/APP_PRIVACY.md`
- `docs/FOUNDATION_MODELS_SETUP.md`
- `docs/APPLE_PLATFORM_FEATURE_AUDIT.md`
- `docs/STOREKIT_SETUP.md`
- `docs/TESTFLIGHT_UPLOAD.md`

## 実装済み

### プロジェクト構成

- `project.yml`
  - XcodeGen用設定
  - iOS 26.0 deployment target
  - iPhone向け設定（`TARGETED_DEVICE_FAMILY: "1"`）
  - Google Mobile Ads SDK（AdMob）SPM dependency
  - AdMob test App ID / banner ad unit build settings
  - `Pribye` app target
  - `PribyeTests` unit test target
- `.github/workflows/ios.yml`
  - GitHub Actions macOS runnerで `xcodegen generate` と `xcodebuild test` を実行
- `.github/workflows/testflight.yml`
  - GitHub Actions macOS runnerで署名付きarchiveを作成し、TestFlightへuploadする手動実行workflow
  - 手動実行に加え、`iOS` workflowが`main`へのpushで成功した場合に自動実行
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
- `Pribye/Services/ImageAssetService.swift`
- `Pribye/Services/PurchaseService.swift`
- `Pribye/Services/SampleDataFactory.swift`
- `Pribye/Views/TaskListView.swift`
- `Pribye/Views/PrintListView.swift`
- `Pribye/Views/DetailViews.swift`
- `Pribye/Views/CaptureFlowView.swift`
- `Pribye/Views/CameraImagePicker.swift`
- `Pribye/Views/EvidenceHighlightView.swift`
- `Pribye/Views/ManualTaskView.swift`
- `Pribye/Views/SettingsView.swift`
- `Pribye/Views/Components.swift`

### モデル

`Document -> Page -> OCRObservation -> ExtractedTask` を基本構造として実装済み。

- `DocumentRecord`
  - プリント単位
  - 処理状態、ライフサイクル、代表写真アセットID、画像ハッシュ、サムネイル、全ページOCR全文を保持
- `PageRecord`
  - 複数ページ対応
  - ページごとの写真アセットID、画像ハッシュ、OCRテキスト、AI補正後OCRテキスト、四隅補正座標を保持
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
- タスク詳細からの根拠ハイライト表示

UI方針:

- `TabView` は `タスク / プリント / 設定`
- 撮影はシートで表示
- 広告は一覧画面下部のAdMob bannerのみ。SDK未解決時だけプレースホルダーにフォールバック
- 撮影、補正、確認、詳細画面には広告を表示しない
- 解析後の確認画面は設定でON/OFF可能

### サービス

実装済み:

- `VisionOCRService`
  - Vision OCR用
- `DocumentAnalyzer`
  - AI抽出境界
- `FoundationModelsDocumentAnalyzer`
  - `FoundationModels` framework が利用でき、`SystemLanguageModel.default.isAvailable` がtrueの場合は `LanguageModelSession` の structured generation を利用
  - 複数ページプリントでは、全ページ一括投入ではなく、対象ページ + 次ページ冒頭の文脈でページ単位解析する
  - SDK未解決、Apple Intelligence利用不可、モデル未準備の場合は `HeuristicDocumentAnalyzer` へフォールバック
- `FoundationModelsOCRTextCorrector`
  - `FoundationModels` framework が利用できる場合、OCR後・タスク抽出前に明らかなOCR誤認だけをオンデバイス補正
  - 複数ページプリントでは、対象ページ + 次ページ冒頭の文脈でページ単位補正する
  - 補正失敗、Apple Intelligence利用不可、モデル未準備の場合は元OCRテキストをそのまま利用
- `HeuristicDocumentAnalyzer`
  - OCRテキストから期限/期間と行動らしい文を簡易抽出
- `DateRangeParser`
  - `6月20日まで`、`6/15〜6/20` などを解析
- `EventKitCalendarService`
  - ユーザー操作によるカレンダー登録
- `CSVExporter`
  - 設定画面からCSV共有
- `ImageAssetService`
  - 補正後画像の写真ライブラリ保存
  - Photos asset ID と画像ハッシュ保存
  - 元画像削除、写真アクセス拒否、画像変更検知
- `ImageProcessingService`
  - 四隅座標からCore Imageのperspective correctionを実行
- `PurchaseService`
  - StoreKit 2で広告非表示課金 `com.pribye.remove_ads` の読み込み、購入、復元
  - StoreKit transaction updates を監視し、購入状態を `adsRemoved` に反映

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
- 四隅補正座標の保存

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
- XcodeGenの `sources` 除外を `Resources/Info.plist` のみに変更し、`Assets.xcassets` がasset catalogとしてcompileされるように修正。
- `altool` がupload失敗ログを出してもstep成功扱いになるケースを防ぐため、uploadログ内の失敗文字列を検出してworkflowを失敗させるように修正。
- 実機クラッシュログ `Pribye-2026-06-19-192256.ips` で、補正後画像の写真ライブラリ保存時に `PHPhotoLibrary` の callback が `com.apple.PHPhotoLibrary.changes` queue から呼ばれ、`@MainActor` 隔離された closure が Swift 6 の actor isolation runtime check で `EXC_BREAKPOINT` になる問題を確認。`ImageAssetService` の Photos callback 処理を nonisolated helper に分離して修正。
- iOS CI run `27857552838` で、`ImageAssetService.loadImageData` の `withCheckedThrowingContinuation` に `return` がなく Swift 6 build error になった問題を確認。`return try await` に修正し、あわせて `createPhotoAsset` の Photos callback で mutable captured var 警告が出ないよう同期 state に分離。

## 現在の重要な制約

### Foundation Models

`FoundationModelsDocumentAnalyzer` は条件付きで実API接続済みです。

実装:

- `canImport(FoundationModels)` の環境では `LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)` を使用。
- 出力は `@Generable` DTOで受け、既存の `AnalysisResult` / `TaskDraft` に変換。
- Foundation Models が利用不可の場合は、CIと非対応端末で動くよう `HeuristicDocumentAnalyzer` にフォールバック。

注意:

- Windows環境では `FoundationModels` framework のコンパイル確認とApple Intelligence対応実機検証はできていません。
- 実機確認手順は `docs/FOUNDATION_MODELS_SETUP.md` に記載済み。

### カメラ・四隅補正

現在の撮影フローは、VisionKit書類スキャン、実機カメラ撮影フォールバック、`PhotosPicker`、デモデータ追加に対応しています。

実装済み:

- `VisionKit` / `VNDocumentCameraViewController` による標準書類スキャン
- `VNDocumentCameraScan` が返す複数ページを1プリント内の複数 `PageRecord` として保持
- `UIImagePickerController` による実機カメラ撮影フォールバック
- 四隅ドラッグ操作
- 選択中頂点と接続線の拡大確認
- Core Image `CIPerspectiveCorrection` による補正後画像生成
- 補正後画像の写真ライブラリ保存
- Photos asset ID 保存
- 画像ハッシュ生成と、削除/権限拒否/変更検知
- タスク詳細からのOCR根拠ハイライト表示

注意:

- OCR座標とハイライト画像の座標系を一致させるため、Pageに紐づけるPhotos assetはページごとの補正後画像です。DocumentのPhotos assetは代表画像として1ページ目を指します。
- Photos保存後の再取得で未編集画像を変更済み扱いしにくくするため、補正後画像はPNGデータとして保存し、ハッシュも画面スケール非依存のPNG描画データから生成します。
- `PHPhotoLibrary` / `PHImageManager` の completion handler はMainActor上で直接定義しない。Swift 6のactor isolation runtime checkで実機クラッシュする可能性があるため、Photos callback は nonisolated helper に閉じ込める。
- Windows環境ではVisionKit書類スキャン、実機カメラ、Photos権限、Core Image補正、ハイライト表示の実機検証はできていません。TestFlightまたはXcode 26環境で確認してください。

### 広告・課金

広告表示はGoogle Mobile Ads SDK（AdMob）、課金はStoreKit 2のアプリ内コードを実装済みです。

実装済み:

- 一覧画面下部のAdMob anchored adaptive banner
- SDK未解決環境での広告プレースホルダーフォールバック
- Google公式テスト App ID / banner ad unit ID
- `GADApplicationIdentifier`
- Google公式quick startから抽出した `SKAdNetworkItems`
- 設定画面の広告非表示購入/復元UI
- StoreKit product ID: `com.pribye.remove_ads`
- 購入または復元済み entitlement がある場合、`adsRemoved` を有効化して広告プレースホルダーを非表示

未実装:

- AdMob本番 App ID / banner ad unit ID への差し替え
- App Store Connect上のアプリ内課金商品 `com.pribye.remove_ads` 作成

AdMob設定手順は `docs/ADMOB_SETUP.md` に作成済み。

App Store用のプライバシー申告メモは `docs/APP_PRIVACY.md` に作成済み。AdMob採用後は `Data Not Collected` のまま提出できないため、Google Mobile Ads SDK のdata disclosureを確認してApp Store Connect申告を更新する必要があります。

App Store Connect上のアプリ内課金商品作成手順は `docs/STOREKIT_SETUP.md` に作成済み。

AdMobや将来の広告SDKへ、プリント画像、OCR、タスク名、抽出内容を渡さない方針を守る必要があります。

## 次にやること

優先度順:

1. ユーザー承認後にpushし、`.github/workflows/ios.yml` の iOS CI と自動TestFlight Uploadが成功するか確認する。pushするとmacOS Actions無料枠を消費する。
2. TestFlightでVisionKit複数ページ書類スキャン、ページ切替付き四隅補正、ページごとの写真保存、画像ハッシュ、根拠ハイライトを確認する。
3. `docs/FOUNDATION_MODELS_SETUP.md` に沿って、Foundation Modelsのタスク抽出とOCR補正をXcode 26 / 対応実機で検証する。
4. `docs/APPLE_PLATFORM_FEATURE_AUDIT.md` に沿って、次に採用するApple標準機能を判断する。
5. `docs/ADMOB_SETUP.md` に沿って、AdMob本番 App ID / banner ad unit IDへ差し替える。
6. `docs/APP_PRIVACY.md` に沿って、AdMob採用後のApp Store privacy answersを更新する。
7. `docs/STOREKIT_SETUP.md` に沿って、App Store Connectで広告非表示のアプリ内課金商品 `com.pribye.remove_ads` を作成し、StoreKit購入を検証する。

## 次チャットでの推奨依頼

```text
HANDOFF.md を読んで、プリバイ開発の現在地を把握してください。
pushはまだしないでください。GitHub Actions無料枠を節約したいので、必要な作業はまずローカルで止めてください。
TestFlight upload 用のGitHub Actions secretsは登録済みです。
次は、ユーザー承認後にpushし、iOS CIと自動TestFlight Uploadの結果を確認してください。
```

## 注意

- `main` にpushするとGitHub Actionsが走り、iOS CI成功後にTestFlight Uploadも自動実行される。無料枠節約のため、pushはユーザー確認後に行う。
- private repo の macOS Actions は無料枠を消費する。
- ローカルcommitだけならActionsは走らない。
- Macがない前提では、TestFlight upload はGitHub Actionsで行う想定。
- `input` フォルダと `Agent.md` は元資料・補助資料として残す。不要に削除しない。
- 細かい分類、優先度、場所、全文検索中心機能、クラウド同期、ユーザーアカウント、家族共有は現時点の設計対象外。勝手に追加しない。
