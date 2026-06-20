# Foundation Models Setup

`FoundationModelsDocumentAnalyzer` と `FoundationModelsOCRTextCorrector` は Foundation Models 実APIへ接続済みです。`FoundationModels` framework が解決でき、`SystemLanguageModel.default.isAvailable` がtrueの場合は `LanguageModelSession` を使います。SDK未解決、Apple Intelligence利用不可、モデル未準備、モデル出力不正の場合はフォールバックせず解析失敗として扱います。

## 実装対象

更新する場所:

- `Pribye/Services/DocumentAnalyzer.swift`
- `Pribye/Services/OCRTextCorrector.swift`
- `FoundationModelsDocumentAnalyzer.analyze(pages:)`
- `FoundationModelsOCRTextCorrector.correct(pages:)`

変更しない境界:

- `DocumentAnalyzer` protocol
- `OCRPageSnapshot`
- `TaskDraft`
- `AnalysisResult`

## 検証環境

必要なもの:

- Xcode 26 以降
- iOS 26 SDK
- Apple Intelligence / Foundation Models 対応実機
- 日本語OCRテキストを含む実プリント画像

## 実装方針

1. Xcode 26 で `FoundationModels` のコンパイルが通ることを確認する。
2. Apple Intelligence対応実機で `SystemLanguageModel.default.isAvailable` がtrueになることを確認する。
3. 入力は OCR テキストと観測行IDだけにする。画像そのものはモデルへ渡さない。
4. 複数ページプリントでは、全ページ一括ではなく、対象ページ + 次ページ冒頭の文脈でページ単位解析する。
5. 返却形式は `AnalysisResult` に正規化する。
6. 実APIが利用不可の場合、低精度fallbackに進まず、Apple Intelligenceをオンにする案内または解析失敗として見えることを確認する。

## Prompt 要件

抽出対象:

- プリント名
- タスク名
- 期限または期間
- 根拠テキスト
- 根拠に対応する OCR observation ID

OCR補正:

- 明らかなOCR誤認だけを補正する
- 元OCRにない内容を追加しない
- observation ID と行の対応を維持する

抽出しない:

- カテゴリ
- 優先度
- 場所
- 詳細な全文要約

禁止:

- 外部AI APIへ送信する実装
- OCRに存在しない座標や根拠IDの生成
- ユーザー確認コストが増える属性追加

## TestFlight 確認

- 期限行からタスクが作られる。
- 期間行から開始日/終了日つきタスクが作られる。
- 根拠ハイライトが該当行に重なる。
- 複数ページスキャンで、2ページ目以降の根拠ハイライトが該当ページ画像に重なる。
- OCR誤認例（例: `2タ` -> `フタ`）が補正され、元OCRも詳細画面で確認できる。
- モデル出力が空または不正な場合、解析失敗UIから再解析/手動登録へ進める。
- Apple Intelligence が使えない端末や設定OFFの状態でクラッシュせず、Apple Intelligenceをオンにする案内が出る。

## 注意

Apple Developer Documentation は通常HTMLではJavaScript必須ですが、DocC JSONから以下を確認済みです。

- `LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)`
- `LanguageModelSession.Response.content`
- `@Generable(description:)`
- `@Guide(description:)`
- `SystemLanguageModel.default.isAvailable`

ただし、Windows環境では `FoundationModels` framework 自体をコンパイルできないため、Xcode 26 / 対応実機での最終確認が必要です。
