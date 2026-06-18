# 実装メモ

## 設計矛盾の扱い

- 「確認を毎回必須にしない」と「AI結果確認画面」は、設定 `showReviewAfterAnalysis` で両立する。初期値は確認画面を開くが、ユーザーが不要と判断したら解析後に自動保存へ切り替えられる。
- 「ローカル処理」と「広告」は、プリント画像・OCR・タスク内容を広告SDKへ渡さないことで境界を引く。広告通信自体はApp Storeのプライバシー申告対象として扱う。
- 「原本は写真ライブラリのみ」と「根拠ハイライト」は、アプリ内にサムネイル・画像ハッシュ・OCR座標だけを保存し、原本が消えた場合はハイライト不可にする。
- 「Apple Intelligence対応端末のみ」は、iOS 26以上をdeployment targetにし、AI可用性は `AppleIntelligenceAvailability` で集約する。

## Foundation Models

`DocumentAnalyzer` はプロトコルで分離済み。`FoundationModelsDocumentAnalyzer` はFoundation Modelsを接続するための唯一の差し替え地点で、現在はCIとWindows編集環境で安全に動かすため `HeuristicDocumentAnalyzer` にフォールバックしている。

実機またはGitHub ActionsのXcode 26環境でFoundation Models APIの正確なSwiftインターフェースを確認したら、このファイルだけを更新して本接続する。

## クラウドビルド

ローカルにMac/Xcodeがない前提で、GitHub Actionsが以下を行う。

1. Xcode 26系を選択する。
2. XcodeGenをインストールする。
3. `project.yml` から `Pribye.xcodeproj` を生成する。
4. 利用可能なiPhone Simulatorを選び、`xcodebuild test` を実行する。
