# Codex Automation Summary

このファイルは、AM3自動実行の重要な判断、完了事項、次回へ残す要点だけを記録します。

詳細ログ、レート制限確認結果の生ログ、GitHub Actions全文ログ、一時メモ、プロンプト全文、会話ログ、自動化ツールのローカル状態は `.codex-local/` に保存し、Git管理しません。

## 現在の運用

- automation表示名: `Pribye AM3 Task Runner`
- automation ID: `pribye-am3-task-runner`
- 実行時刻: 毎日 日本時間AM3:00
- 入力元: `input/改善要望_*.md` のうちテンプレートを除くローカル作業ファイル、GitHub PR、GitHub Actions失敗run
- テンプレート: `input/改善要望_TEMPLATE.md`
- タスク台帳: `docs/CODEX_TASKS.md`
- 確認待ち: `docs/CODEX_PENDING_CONFIRMATIONS.md`
- ローカル専用ログ: `.codex-local/`

## 重要な判断

- `input/改善要望_TEMPLATE.md` はタスク化対象から除外する。
- 改善要望は `input/改善要望_YYYYMMDD_短い名前.md` としてローカル追加し、Git管理しない。
- commit前レビューは `gpt-5.5`、または利用可能な最上位モデルで行う。
- GitHub Actions失敗は `CI修正` タスクとして `docs/CODEX_TASKS.md` に追加する。
- GitHub Actions全文ログや日次詳細ログはGit管理しない。
- pushは、タスク完了、未解決確認なし、review済みcommitのみの状態に加えて、ユーザーがその時点で明示的にpushを承認している場合のみ行う。

## 完了事項

| date | summary |
| --- | --- |
| 2026-06-24 | `AI解析モデルの差し替え` と `通知機能追加` を task 化し、通知は Apple公式ドキュメント確認と TestFlight での背景実行成立性検証を先行する方針にした。GitHub PR は open/all ともに 0 件、最新失敗 run は `27874312688` で `ModelStateTests` の期待値不一致だった。 |
| 2026-06-25 | Apple公式ドキュメントを確認し、`User Notifications` はローカル通知をサポートするが配信保証はないこと、`Background Tasks` は framework-provided task で数分規模の背景処理を扱うこと、`beginBackgroundTask` は有限時間で明示終了が必要なことを確認した。 |
| 2026-06-25 | GitHub PR は 0 件、最新 Actions は iOS run `27887769614` と TestFlight run `27887824899` が成功済みで、新規 CI 修正タスクはなし。通知機能は前面バナー、初回解析開始時の通知許可要求、背景時のローカル通知要求、成功/失敗のタブ遷移ロジック、通知タップのbufferingまで実装した。 |
| 2026-06-26 | GitHub PR は 0 件、最新 Actions は iOS run `27887769614` と TestFlight run `27887824899` が成功済みで、新規 CI 修正タスクはなし。通知機能は `AnalysisNotificationStore` の前面/背景分岐を unit test で固定した。 |
| 2026-06-27 | GitHub PR は 0 件。6月26日の iOS 失敗 run `28207739501`、`28233227662`、`28240730883` は後続 iOS run `28241199526` と TestFlight run `28241501046` の成功で解消済みとして台帳へ記録した。Gemma 4 E4B差し替えは、LiteRT-LM依存、モデルDL/検証、設定/撮影導線、本番Analyzer切替、JSON正規化テストまで実装した。 |
| 2026-06-29 | GitHub PR は 0 件。最新 Actions は iOS run `28241199526` と TestFlight run `28241501046` が成功済みで、新規 CI 修正タスクはなし。Gemma解析でモデル出力 `date` を優先し、欠落時はローカル日付解析へフォールバックする単体テストを追加した。 |
| 2026-06-30 | GitHub PR は 0 件。最新 Actions は iOS run `28241199526` と TestFlight run `28241501046` が成功済みで、新規 CI 修正タスクはなし。Gemma解析でモデル出力の前後に説明文やMarkdown fenceが混ざっても既存JSON抽出処理で正規化できることを単体テストで固定した。 |

## 次回へ残す要点

| date | note |
| --- | --- |
| 2026-06-24 | 通知機能は Apple公式ドキュメント確認後、TestFlight で背景実行の成立性を技術検証して継続可否を決める。CI 失敗は既に後続 run `27874656339` で解消済み。 |
| 2026-06-25 | 通知機能はまだ「確実通知」とは言えない。TestFlight で OCR + Foundation Models の背景完走可否を検証し、成立しない場合は要件を best-effort に落とすか設計見直しが必要。 |
| 2026-06-25 | 通知機能の iOS build、前面バナー表示、通知許可ダイアログ、背景ローカル通知、システム通知タップ遷移は TestFlight または Xcode 26 環境で確認が必要。 |
| 2026-06-26 | Windows環境のため追加した通知unit testは未実行。次回、macOS runner または Xcode 26 環境で `PribyeTests/AnalysisNotificationTests.swift` を含む iOS test を確認する。 |
| 2026-06-27 | Gemma差し替えは Windows環境では iOS build / SPM resolve / 3.66GBモデルDL / LiteRT実機ロード / 抽出精度を未検証。次回はユーザー承認後のpushまたはTestFlightで確認する。 |
| 2026-06-29 | Windows環境のため追加した Gemma 日付優先/fallback 単体テストは未実行。次回、macOS runner または Xcode 26 環境で `PribyeTests/DocumentAnalyzerTests.swift` を含む iOS test を確認する。 |
| 2026-06-30 | Windows環境のため追加した Gemma preamble/fence 単体テストは未実行。次回、macOS runner または Xcode 26 環境で `PribyeTests/DocumentAnalyzerTests.swift` を含む iOS test を確認する。 |
