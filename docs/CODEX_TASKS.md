# Codex タスク台帳

このファイルは、AM3自動実行で扱う改善要望、GitHub PR、GitHub Actions失敗のタスク台帳です。

## 運用ルール

- `input/改善要望_*.md` のうち、`input/改善要望_TEMPLATE.md` を除くローカル作業ファイルを改善要望の入力として扱う。
- `input/改善要望_TEMPLATE.md` はテンプレートなのでタスク化しない。
- 個別の改善要望マークダウンはGit管理しない。必要ならテンプレートからローカル作成する。
- GitHub PR と GitHub Actions の失敗runも毎日確認する。
- 未記入項目や仕様判断が必要な場合は推測せず、`docs/CODEX_PENDING_CONFIRMATIONS.md` に確認事項を残す。
- commit前レビューは必ず `gpt-5.5`、または利用可能な最上位モデルで行う。
- レビュー必須タスクで `gpt-5.5` がレート制限中の場合、そのタスクのcommitは止め、独立して進められる別タスクを進める。

## モデル割り当て基準

- `gpt-5.4-mini`: 小さい文書修正、単純なUI文言、局所的なテスト追加。
- `gpt-5.4`: 通常の実装、既存設計に沿う修正。
- `gpt-5.5`: 改善案レビュー、CI失敗分析、設計判断、Foundation Models、CI/TestFlight、課金/広告/プライバシー、commit前レビュー。

## タスク一覧

| id | source | status | assigned_model | success_criteria | verification | review_result |
| --- | --- | --- | --- | --- | --- | --- |
