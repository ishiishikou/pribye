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

## 次回へ残す要点

| date | note |
| --- | --- |
