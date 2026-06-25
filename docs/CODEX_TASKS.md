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
| task-20260624-ai-model-swap | `input/改善要望_20260623_AI解析モデルの差し替え.md` | pending | gpt-5.5 | `LiteRT-LM + Gemma 4 E4B` で本番解析を差し替え、モデル取得・検証・解析・保存・根拠ハイライトまで動く | `Gemma 4 E4B` の抽出プロンプト検証と iOS / TestFlight でのモデルDL後動作確認 | not reviewed yet |
| task-20260624-notification | `input/改善要望_20260623_通知機能追加.md` | implemented_pending_testflight | gpt-5.5 | 新規取込と再解析の完了通知を実装し、前面バナー・背景通知・タップ遷移が要件どおりに動く | 2026-06-25: 前面バナー、初回解析開始時の通知許可要求、背景時のローカル通知要求、抽象文言、成功/失敗のタブ遷移ロジック、通知タップのinbox bufferingを実装。`git diff --check` passed。Windows環境のため iOS build / TestFlight / 背景完走 / システム通知タップは未検証 | gpt-5.5 final review passed after fixing notification tap routing, stale scenePhase, cold-start tap buffering, and Swift 6 delegate Sendable risk |
| ci-20260624-ios-run-27874312688 | `https://github.com/ishiishikou/pribye/actions/runs/27874312688` | completed | gpt-5.5 | `build-test` の失敗原因を特定し、後続 run で再発なく成功する状態に戻す | job `82491148609` の失敗ログ確認と、後続 successful run `27874656339` の確認 | resolved by later run `27874656339`; failure was `ModelStateTests.testDocumentStatusSeparatesInternalAndUserLabels` expecting `解析中` but seeing `AI解析中` |
