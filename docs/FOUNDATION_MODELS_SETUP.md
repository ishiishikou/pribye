# Foundation Models Setup

`FoundationModelsDocumentAnalyzer` は Foundation Models 実APIへ接続済みです。`FoundationModels` framework が解決でき、`SystemLanguageModel.default.isAvailable` がtrueの場合は `LanguageModelSession` を使います。SDK未解決、Apple Intelligence利用不可、モデル未準備の場合は CI と Windows 編集環境で安全に動かすため、`HeuristicDocumentAnalyzer` へフォールバックします。

## 実装対象

更新する場所:

- `Pribye/Services/DocumentAnalyzer.swift`
- `FoundationModelsDocumentAnalyzer.analyze(pages:)`

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
4. 返却形式は `AnalysisResult` に正規化する。
5. 実APIが利用不可の場合のフォールバック挙動がユーザー体験上問題ないか確認する。

## Prompt 要件

抽出対象:

- プリント名
- タスク名
- 期限または期間
- 根拠テキスト
- 根拠に対応する OCR observation ID

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
- モデル出力が空の場合、解析失敗UIから再解析/手動登録へ進める。
- Apple Intelligence が使えない端末でクラッシュしない。

## 注意

Apple Developer Documentation は通常HTMLではJavaScript必須ですが、DocC JSONから以下を確認済みです。

- `LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)`
- `LanguageModelSession.Response.content`
- `@Generable(description:)`
- `@Guide(description:)`
- `SystemLanguageModel.default.isAvailable`

ただし、Windows環境では `FoundationModels` framework 自体をコンパイルできないため、Xcode 26 / 対応実機での最終確認が必要です。
