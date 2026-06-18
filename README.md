# プリバイ

プリバイ（プリントばいばい）は、学校や幼稚園などの紙プリントを撮影し、必要な行動だけをタスク化するiPhoneアプリです。

## 技術方針

- iOS 26+
- SwiftUI
- SwiftData
- Vision OCR
- Foundation Models連携用の `DocumentAnalyzer` 境界
- GitHub Actions + XcodeGen によるクラウドビルド

## Macなし開発フロー

1. Windows上でSwiftソースと `project.yml` を編集する。
2. GitHubへpushする。
3. GitHub ActionsのmacOS runnerで `xcodegen generate` と `xcodebuild test` を実行する。
4. App Store公開前にApple Developer Program、Bundle ID、Signing、App Store Connect、TestFlightを設定する。

## プライバシー方針

プリント画像、OCR全文、抽出タスク内容は外部AI APIへ送信しません。広告SDKを追加する場合も、プリント内容・画像・OCR・タスク名を広告SDKへ渡さない設計を維持します。
