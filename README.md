# プリバイ

プリバイ（プリントばいばい）は、学校や幼稚園などの紙プリントを撮影し、必要な行動だけをタスク化するiPhoneアプリです。

## 技術構成

- iOS 26+
- SwiftUI / SwiftData
- Vision OCR
- LiteRT-LM / Gemma 4 E4Bによるオンデバイス解析
- Foundation Models連携用の `DocumentAnalyzer` 境界
- XcodeGen
- GitHub ActionsのmacOS runnerによるクラウドビルド

## ビルド方針

Xcodeプロジェクトは `project.yml` から生成します。`iOS` と `TestFlight Upload` workflowは手動実行です。

1. Swiftソースと `project.yml` を編集する。
2. GitHubへpushする。
3. GitHub ActionsでLiteRT-LMの準備、`xcodegen generate`、build/testを実行する。
4. TestFlight workflowではGitHub Actions Secretsに保存した署名素材を使用する。

署名鍵、証明書、provisioning profile、API key、実データはリポジトリへcommitしません。

## プライバシー方針

プリント画像、OCR全文、抽出タスク内容は外部AI APIへ送信しません。広告SDKにも、プリント内容、画像、OCR、タスク名を渡さない設計を維持します。

公開issue、pull request、Actionsログへ、実際の学校プリント、OCR結果、氏名、連絡先、秘密鍵、証明書、API keyを貼らないでください。

## 公開範囲

このリポジトリは開発状況とソースコードを閲覧可能にするため公開しています。commit履歴、pull request、GitHub Actionsログ、設計・運用文書も公開対象です。

## ライセンス

このリポジトリはソース閲覧可能ですが、オープンソースライセンスではありません。明示的に別条件が記載された第三者コンポーネントを除き、コード、文書、画像その他の独自成果物の権利は留保されています。詳細は `LICENSE` を参照してください。

セキュリティ上の問題は `SECURITY.md` の手順に従って報告してください。
