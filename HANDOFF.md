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
  - `workflow_dispatch` の手動実行のみ
  - `xcodegen generate` と `xcodebuild test` を macOS runner で実行
- workflow: `.github/workflows/testflight.yml`
  - TestFlight upload用workflow。`workflow_dispatch` の手動実行のみ
- 確認済みの成功run:
  - `27737585159` `Document TestFlight upload preparation`
  - `27737437580` `Mark Bundle ID registration complete`
  - `27737095844` `Configure Apple development team`
  - `27736637531` `Add required app bundle metadata`

注意:

- private repository の GitHub-hosted macOS runner は GitHub Actions の無料枠を消費する。
- workflow はすべて手動実行のみ。push しても GitHub Actions は自動起動しない。
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
  - GitHub Actions macOS runnerで `xcodegen generate` と `xcodebuild test` を手動実行
- `.github/workflows/testflight.yml`
  - GitHub Actions macOS runnerで署名付きarchiveを作成し、TestFlightへuploadする手動実行workflow
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
- `Pribye/Services/AppleIntelligenceChatService.swift`
- `Pribye/Services/OCRService.swift`
- `Pribye/Services/CalendarService.swift`
- `Pribye/Services/CSVExporter.swift`
- `Pribye/Services/ImageAssetService.swift`
- `Pribye/Services/PurchaseService.swift`
- `Pribye/Views/TaskListView.swift`
- `Pribye/Views/PrintListView.swift`
- `Pribye/Views/AIExperimentView.swift`
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
  - 処理状態、ライフサイクル、代表画像参照、画像ハッシュ、サムネイル、全ページOCR全文を保持
- `PageRecord`
  - 複数ページ対応
  - ページごとの画像参照、画像ハッシュ、OCRテキスト、四隅補正座標を保持
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
- 撮影/補正/バックグラウンド解析フロー
- 手動タスク追加
- 設定
- タスク詳細からの根拠ハイライト表示。根拠テキストと画像ハイライトを同じ画面で確認できる
- タスク詳細はタイトル/メモを直接編集できる画面として扱い、押しても何も起きない編集ボタンは置かない
- 手動タスク追加では、保存/キャンセルをナビゲーションバーに表示し、入力中でも登録操作へ到達しやすくしている

UI方針:

- `TabView` は `タスク / プリント / AI実験 / 設定`
- 撮影はシートで表示
- 広告はタスク一覧/プリント一覧の下部固定AdMob bannerのみ。SDK未解決時だけプレースホルダーにフォールバック
- 撮影、補正、詳細画面には広告を表示しない
- 解析開始後は撮影シートを閉じ、プリント一覧へ移動する。ユーザーは解析中に画面を離れてよい。
- プリント一覧では `画像処理中`、`OCR中`、`AI解析中` の大まかな進捗を表示する。
- プリント一覧では解析失敗したプリント行に失敗理由を表示し、詳細画面に入る前に次の対応を判断しやすくしている。
- デモデータ追加UIと `SampleDataFactory` は削除済み。
- `AI実験` タブは開発用。プロンプトとOCR文章を手入力し、Apple Intelligenceの自由応答を確認できる。本番のタスク抽出・保存済みプリント・タスク生成には接続しない。App Store提出前に削除する。

### サービス

実装済み:

- `VisionOCRService`
  - Vision OCR用
- `DocumentAnalyzer`
  - AI抽出境界
- `FoundationModelsDocumentAnalyzer`
  - `FoundationModels` framework が利用でき、`SystemLanguageModel.default.isAvailable` がtrueの場合は `LanguageModelSession` の自由応答を短いプロンプトで段階実行する
  - 解析手順は、OCR全文を「要約してください」で要約し、要約文から「保護者のタスクを抽出してください」でタスク本文を抽出し、各タスク本文から「タスクを1行20文字以内で生成してください。」でタイトルを生成し、最後にOCR全文から根拠文章を抽出する
  - 保存時は、タイトル=生成タイトル、メモ=抽出タスク本文、根拠=OCR全文から抽出した根拠文章
  - 根拠ハイライト用の `evidenceObservationID` は、抽出した根拠文章に最も近いOCR行をローカル照合して設定する
  - 期限/期間はAIに日付形式を要求せず、抽出タスク本文を `DateRangeParser` でローカル解析する
  - 複数ページプリントでは、全ページ一括投入ではなく、対象ページ + 次ページ冒頭の文脈でページ単位解析する
  - SDK未解決、Apple Intelligence利用不可、モデル未準備の場合はフォールバックせず、解析失敗として表示する
  - 現在は本番経路ではなく、開発・比較用として残している
  - 開発中は設定画面の `要約プロンプト` で最初の要約ステップだけを上書きできる。既定値は `要約してください`。App Store提出前にこの入力欄は削除する
- `AppleIntelligenceChatService`
  - 開発用 `AI実験` タブ専用。`LanguageModelSession` の自由応答で、プロンプト + OCR文章に対するApple Intelligenceの回答を確認する
  - structured generation、JSON生成、タスク保存、OCR補正、既存解析パイプラインには接続しない
  - Apple Intelligence利用不可時はフォールバックせず、オンにする案内を表示する
- `DocumentAnalysisPipeline`
  - 撮影後解析とプリント詳細からの再解析で共通利用するタスク抽出パイプライン
  - ページ単位解析、根拠行補正、`DocumentRecord` への反映を担当
  - 本番経路は `GemmaDocumentAnalyzer` を既定にしているため、Gemma解析ではページ間の重複排除を行わない
- `GemmaDocumentAnalyzer`
  - `LiteRT-LM + Gemma 4 E4B` による本番タスク抽出経路
  - 既存のVision OCR結果と observation ID を単一プロンプトへ渡し、JSON出力を `TaskDraft` に正規化する
  - 解析はページ単位で行い、対象ページ末尾が明らかに継続している場合だけ次ページ冒頭を `CONTEXT` として渡す
  - モデル未ダウンロード時は低精度fallbackを使わず `modelNotReady` として解析失敗にする
  - LiteRT初期化/生成失敗時は `modelLoadFailed` として解析失敗にする
  - JSON不正、空タスク、存在しない observation ID は `malformedModelOutput` として解析失敗にする
- `GemmaModelStore`
  - Hugging Face の `gemma-4-E4B-it.litertlm` を Application Support 配下へユーザー操作でダウンロードする
  - モデルはアプリに同梱しない
  - ダウンロード後に SHA256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` を検証する
  - 設定画面からダウンロード、削除、再ダウンロードができる
- `FoundationModelsOCRTextCorrector`
  - `FoundationModels` framework が利用できる場合、タスク化された根拠行だけをオンデバイス補正
  - 根拠行の前後行、ページ境界では隣接ページの近接行も文脈として渡す
  - 補正文はOCR結果欄には表示せず、タスクの根拠テキストとして表示する
  - 補正失敗、Apple Intelligence利用不可、モデル未準備、モデル出力不正の場合は元OCRテキストへフォールバックせず、解析失敗として表示する
  - 現在の本番解析パイプラインでは、短い段階プロンプトの根拠抽出結果をそのまま根拠テキストに保存するため、この補正サービスは呼び出していない
- `DateRangeParser`
  - `6月20日まで`、`6/15〜6/20` などを解析
- `EventKitCalendarService`
  - ユーザー操作によるカレンダー登録
- `CSVExporter`
  - 設定画面からCSV共有
- `ImageAssetService`
  - カメラ/書類スキャン由来の補正後画像は写真ライブラリへ保存
  - アルバム選択由来の補正後画像は、二重保存を避けるためアプリ内部へ保存
  - Photos asset ID または内部保存ファイル名と画像ハッシュを保存
  - 元画像削除、写真アクセス拒否、画像変更検知
  - プリント削除時に、ユーザー選択で保存画像も削除できる。写真ライブラリ上の画像とアプリ内部保存画像の両方を対象にする
- `ImageProcessingService`
  - 四隅座標からCore Imageのperspective correctionを実行
- `PurchaseService`
  - StoreKit 2で広告非表示課金 `com.pribye.remove_ads` の読み込み、購入、復元
  - StoreKit transaction updates を監視し、購入状態を `adsRemoved` に反映
- `AnalysisNotificationService`
  - 新規取込と再解析の解析開始時に通知許可を初回だけ要求
  - 解析成功/失敗時に、アプリ前面では画面上部バナー、背景では抽象文言のローカル通知を出す
  - 通知タップは cold start でも取りこぼしにくいよう inbox にbufferし、成功はタスクタブ、失敗は対象プリント詳細へ遷移する
  - 背景中に OCR + Foundation Models が完走する保証は未検証。TestFlight または Xcode 26 環境で確認が必要

### テスト

追加済み:

- `PribyeTests/DateRangeParserTests.swift`
- `PribyeTests/DocumentAnalyzerTests.swift`
- `PribyeTests/ModelStateTests.swift`

対象:

- 日付/期間パース
- Foundation Models利用不可時に解析失敗になること
- Apple Intelligence自由応答サービスの空入力と利用不可時エラー
- Gemma JSON正規化、不正出力拒否、ページ単位解析、条件付きCONTEXT付与
- タスク完了状態とライフサイクル
- Document状態表示
- 四隅補正座標の保存

## 直近で解決した問題

CIを通すために以下を修正済み:

- GitHub Actions workflow をすべて `workflow_dispatch` の手動実行のみに変更し、`push` / `pull_request` / `workflow_run` の自動起動を削除。
- 実機クラッシュログ `Pribye-2026-06-26-224308.ips` で、SwiftUI の `sheet` 表示開始時に `EnvironmentValues.subscript.getter` assertion で落ちる問題を確認。`RouterPath` / `AnalysisNotificationStore` の type-based environment 参照を optional に変更し、sheet 内 `NavigationStack` へ custom environment を明示注入して、環境値欠落経路でもクラッシュしないよう修正。
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
- iOS CI run `27859101646` で、`CapturedPageImage.cropCorners` の default value が `CropPreview.defaultCorners` を参照し、Swift 6でMainActor隔離値扱いになってbuild errorになる問題を確認。四隅初期値をView型から独立したhelperへ分離して修正。
- Gemma解析でモデル出力 `date` がある場合はその日付を優先し、`date` 欠落時はローカル `DateRangeParser` へフォールバックする挙動を単体テストで固定。
- 手動タスク登録で、フォーム末尾の保存ボタンをナビゲーションバーの保存/キャンセルへ移し、空タイトル保存の防止は維持した。

## 現在の重要な制約

### Codex AM3タスク運用

Codexのレート制限とGitHub Actions無料枠を節約するため、AM3自動実行の運用を追加済み。

関連ファイル:

- `input/改善要望_TEMPLATE.md`
  - 改善要望の記入テンプレート
  - コピーして `input/改善要望_YYYYMMDD_短い名前.md` として追加する
- `docs/CODEX_TASKS.md`
  - 改善要望、GitHub PR、GitHub Actions失敗runをタスク化する台帳
- `docs/CODEX_PENDING_CONFIRMATIONS.md`
  - 無人実行中にユーザー確認が必要になった内容を記録する
- `docs/CODEX_AUTOMATION_SUMMARY.md`
  - AM3自動実行の重要な判断、完了事項、次回へ残す要点だけを記録する
- `.codex-local/`
  - 詳細ログ、レート制限確認結果、GitHub Actions全文ログ、一時メモなどのローカル専用置き場。Git管理しない

automation:

- 表示名: `Pribye AM3 Task Runner`
- ID: `pribye-am3-task-runner`
- 実行時刻: 毎日 日本時間AM3:00
- model: `gpt-5.4-mini`

重要な運用:

- `input/改善要望_TEMPLATE.md` はタスク化しない。
- `input/改善要望_*.md` のうちテンプレートを除くローカル作業ファイル、GitHub PR、GitHub Actions失敗runを確認する。
- 個別の改善要望マークダウンはGit管理せず、テンプレートだけGit管理する。
- 改善案レビュー、CI失敗分析、commit前レビューは `gpt-5.5`、または利用可能な最上位モデルで行う。
- commit前レビューが通らない場合はcommitしない。
- pushは、タスク完了、未解決確認なし、review済みcommitのみの状態に加えて、ユーザーがその時点で明示的にpushを承認している場合のみ行う。

### Foundation Models

`FoundationModelsDocumentAnalyzer` は条件付きで実API接続済みですが、現在の本番解析既定経路は `GemmaDocumentAnalyzer` です。

実装:

- `canImport(FoundationModels)` の環境では `LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)` を使用。
- 出力は `@Generable` DTOで受け、既存の `AnalysisResult` / `TaskDraft` に変換。
- Foundation Models が利用不可の場合はフォールバックしない。Apple Intelligenceをオンにする案内または解析失敗として見せる。
- `HeuristicDocumentAnalyzer` は削除済み。低精度fallbackを復活させない。
- Apple Intelligence非対応端末は配布対象外にしたい方針。ただしApple Intelligence専用の `UIRequiredDeviceCapabilities` キーは未確認のため、現時点ではInfo.plistへ推測追加しない。Xcode/Apple資料で確認するまでは、アプリ内の `AppleIntelligenceAvailability` による利用ブロックで対応する。

注意:

- Windows環境では `FoundationModels` framework のコンパイル確認とApple Intelligence対応実機検証はできていません。
- 実機確認手順は `docs/FOUNDATION_MODELS_SETUP.md` に記載済み。
- GitHub Actions run `27861819455`（`probe-foundation-models-image`）で、Xcode 26.3 / iOS 26 SDK上の小さいFoundation Models typecheckは成功。symbol graph検索では `Prompt` / `Transcript` / `Tool` 系は確認できたが、`UIImage`、`Image`、`Vision`、`Media`、`Multimodal` など直接画像入力に見えるFoundationModels APIは確認できなかった。
- GitHub Actions run `27865132074` で `Attachment(CGImage)` を使う概念コードをtypecheckした結果、`cannot find 'Attachment' in scope` で失敗。現在のXcode 26.3 / iOS 26 SDKでは、FoundationModelsへ画像を直接渡す `Attachment` APIは利用不可と判断する。
- GitHub Actions run `27865440946` で `macos-26` / Xcode 26.5（17F42）/ `arm64-apple-ios26.5` targetでも同じ `Attachment(CGImage)` 概念コードをtypecheckしたが、同じく `cannot find 'Attachment' in scope` で失敗。Xcode 26.5でもFoundationModels画像Attachment APIは利用不可と判断する。

### カメラ・四隅補正

現在の撮影フローは、VisionKit書類スキャン、実機カメラ撮影フォールバック、`PhotosPicker` に対応しています。

実装済み:

- `VisionKit` / `VNDocumentCameraViewController` による標準書類スキャン。自動書類検出、自動撮影、連続撮影、四隅調整、台形補正は標準UIに任せる
- `UIImagePickerController` による実機カメラ撮影フォールバック。未補正画像をアプリ側の四隅選択に渡す
- `VNDocumentCameraScan` が返す複数ページを1プリント内の複数 `PageRecord` として保持
- カメラ/写真選択向けの四隅ドラッグ操作
- カメラ/写真選択向けの選択中頂点と接続線の拡大確認
- VisionKit標準スキャンUIの四隅調整だけを独自UIに差し替える公開APIはないため、VisionKit経路では独自四隅調整画面を挟まない
- VisionKit標準スキャンUIが日本語リソースを選ぶよう、アプリの開発言語/ローカライズは日本語に設定
- Core Image `CIPerspectiveCorrection` による補正後画像生成
- カメラ/書類スキャン由来の補正後画像は写真ライブラリへ保存
- アルバム選択由来の補正後画像は、写真ライブラリへ再保存せずアプリ内部へ保存
- Photos asset ID または内部保存ファイル名を保存
- 画像ハッシュ生成と、削除/権限拒否/変更検知
- タスク詳細からのOCR根拠ハイライト表示

注意:

- OCR座標とハイライト画像の座標系を一致させるため、Pageに紐づける画像参照はページごとの補正後画像です。Documentの画像参照は代表画像として1ページ目を指します。
- 保存後の再取得で未編集画像を変更済み扱いしにくくするため、補正後画像はPNGデータとして保存し、ハッシュも画面スケール非依存のPNG描画データから生成します。
- `PHPhotoLibrary` / `PHImageManager` の completion handler はMainActor上で直接定義しない。Swift 6のactor isolation runtime checkで実機クラッシュする可能性があるため、Photos callback は nonisolated helper に閉じ込める。
- Windows環境ではVisionKit書類スキャン、実機カメラ、Photos権限、Core Image補正、ハイライト表示の実機検証はできていません。TestFlightまたはXcode 26環境で確認してください。

### 広告・課金

広告表示はGoogle Mobile Ads SDK（AdMob）、課金はStoreKit 2のアプリ内コードを実装済みです。

実装済み:

- タスク一覧/プリント一覧の下部固定AdMob anchored adaptive banner
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

1. GitHub Actions の `iOS` workflow を手動実行し、CI が成功するか確認する。macOS Actions無料枠を消費する。
2. 必要時に GitHub Actions の `TestFlight Upload` workflow を手動実行し、アップロードが成功するか確認する。macOS Actions無料枠を消費する。
3. TestFlightでVisionKit複数ページ書類スキャン、実機カメラ撮影、写真選択、カメラ/写真選択時の四隅補正、ページごとの画像保存、画像ハッシュ、根拠ハイライト、解析開始後のプリント一覧遷移、再解析、解析完了通知の前面バナー/背景通知/通知タップ遷移を確認する。
4. `AI実験` タブでプロンプトとOCR文章を入力し、Apple Intelligenceの自由応答を実機確認する。
5. 開発中設定の要約プロンプト欄と `AI実験` タブで、短い段階プロンプト方式の抽出精度を実機調整する。
6. プリント削除で「プリントだけ削除」と「プリントと保存画像を削除」の両方を実機確認する。
7. `docs/FOUNDATION_MODELS_SETUP.md` に沿って、Foundation Modelsのタスク抽出とOCR補正をXcode 26 / 対応実機で検証する。
8. `docs/APPLE_PLATFORM_FEATURE_AUDIT.md` に沿って、次に採用するApple標準機能を判断する。
9. `docs/ADMOB_SETUP.md` に沿って、AdMob本番 App ID / banner ad unit IDへ差し替える。
10. `docs/APP_PRIVACY.md` に沿って、AdMob採用後のApp Store privacy answersを更新する。
11. `docs/STOREKIT_SETUP.md` に沿って、App Store Connectで広告非表示のアプリ内課金商品 `com.pribye.remove_ads` を作成し、StoreKit購入を検証する。
12. GitHub CLI token が無効になっている場合は `gh auth login -h github.com` で再認証し、PR と GitHub Actions の最新状態を確認する。

## 次チャットでの推奨依頼

```text
HANDOFF.md を読んで、プリバイ開発の現在地を把握してください。
pushはまだしないでください。GitHub Actions無料枠を節約したいので、必要な作業はまずローカルで止めてください。
TestFlight upload 用のGitHub Actions secretsは登録済みです。
次は、ユーザー承認後にpushし、iOS CIと自動TestFlight Uploadの結果を確認してください。
```

## 注意

- GitHub Actions workflow はすべて手動実行のみ。push だけでは CI / TestFlight upload は始まらない。
- private repo の macOS Actions は無料枠を消費する。
- ローカルcommitだけならActionsは走らない。
- Macがない前提では、TestFlight upload はGitHub Actionsで行う想定。
- `input` フォルダと `Agent.md` は元資料・補助資料として残す。不要に削除しない。
- 細かい分類、優先度、場所、全文検索中心機能、クラウド同期、ユーザーアカウント、家族共有は現時点の設計対象外。勝手に追加しない。
