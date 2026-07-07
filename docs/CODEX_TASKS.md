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
| task-20260624-ai-model-swap | `input/改善要望_20260623_AI解析モデルの差し替え.md` | implemented_pending_ios_verification | gpt-5.5 | `LiteRT-LM + Gemma 4 E4B` で本番解析を差し替え、モデル取得・検証・解析・保存・根拠ハイライトまで動く | 2026-06-27: `LiteRTLM` SPM依存、GemmaモデルDL/削除/ハッシュ検証、設定/撮影導線、本番解析の `GemmaDocumentAnalyzer` 既定化、ページ単位解析、末尾継続時だけ次ページCONTEXT付与、モデル未準備/ロード失敗表示、Gemma JSON正規化/不正出力/ページ単位パイプラインテストを実装。`git diff --check` passed。Windows環境のため iOS build / SPM resolve / 3.66GBモデルDL / TestFlight実機解析は未検証。2026-06-29: Gemma出力の `date` がある場合はモデル日付を優先し、ない場合はローカル `DateRangeParser` にフォールバックする単体テストを追加。フォールバック側は月日まで検証。`git diff --check` passed。Windows環境のため iOS test は未実行。2026-06-30: Gemma出力の前後に説明文やMarkdown fenceが混ざっても既存JSON抽出処理で正規化できることを単体テストで固定。`git diff --check` passed。Windows環境のため iOS test は未実行。2026-07-03: 注入した `GemmaTextGenerating` を使って `GemmaDocumentAnalyzer.analyze` がプロンプト生成とJSON正規化まで通る単体テストを追加。`git diff --check` passed。Windows環境のため iOS test は未実行。2026-07-05: 同差分を再確認し、`git diff --check` passed。Windows環境のため iOS test は未実行 | 2026-06-27: available top-model static review passed after wrapping LiteRT init/generation failures as `modelLoadFailed`, switching LiteRT Swift calls to the documented sync init/createConversation API, and adding malformed Gemma output plus page-scoped pipeline tests。2026-06-29: available top-model static review passed; model-date precedence and local parser fallback assertions match existing implementation without production code changes。2026-06-30: available top-model static review passed; preamble/fence test covers existing parser behavior only and adds no production fallback or behavior change。2026-07-03: available top-model static review passed; injected-generator test exercises existing analyzer boundary only and does not change production behavior。2026-07-05: available top-model static review passed; injected generator is actor-isolated, records prompt without production behavior changes, and asserts the analyzer boundary only |
| task-20260624-notification | `input/改善要望_20260623_通知機能追加.md` | implemented_pending_testflight | gpt-5.5 | 新規取込と再解析の完了通知を実装し、前面バナー・背景通知・タップ遷移が要件どおりに動く | 2026-06-25: 前面バナー、初回解析開始時の通知許可要求、背景時のローカル通知要求、抽象文言、成功/失敗のタブ遷移ロジック、通知タップのinbox bufferingを実装。`git diff --check` passed。2026-06-26: 前面時はバナー表示、背景時はローカル通知serviceへ委譲する `AnalysisNotificationStore` unit tests を追加。`git diff --check` passed。Windows環境のため iOS build / TestFlight / 背景完走 / システム通知タップは未検証 | 2026-06-25: gpt-5.5 final review passed after fixing notification tap routing, stale scenePhase, cold-start tap buffering, and Swift 6 delegate Sendable risk. 2026-06-26: available top-model static review passed for added notification store tests |
| task-20260706-task-filter-empty-state | `input/改善要望_20260705_操作体験の向上.md` | implemented_pending_ios_verification | gpt-5.4-mini | タスク一覧で未完了/完了済みの切り替えが空状態でも失われず、完了済みタスクへ迷わず到達できる | 2026-07-06: タスクが存在する場合は表示セグメントを常に出し、選択中フィルタだけ空の場合は切り替え案内の空状態をリスト内に表示するよう `TaskListView` を更新。`git diff --check` passed。Windows環境のため iOS build / SwiftUI表示確認は未実行 | 2026-07-06: available top-model static review passed; change is limited to TaskListView empty/filter presentation and does not alter task data, routing, or completion behavior |
| task-20260707-print-failure-reason-row | `input/改善要望_20260705_操作体験の向上.md` | implemented_pending_ios_verification | gpt-5.4-mini | プリント一覧で解析失敗したプリントの理由が詳細画面へ入らなくても分かる | 2026-07-07: `PrintListView` のプリント行で `解析失敗` の場合に `failureReason.message` を2行まで表示するよう更新。GitHub PR は open 0件、最新 Actions は iOS run `28241199526` / TestFlight run `28241501046` が成功で、新規CI修正タスクなし。`git diff --check` passed。Windows環境のため iOS build / SwiftUI表示確認は未実行 | 2026-07-07: available top-model static review passed; change is read-only UI presentation of existing failure reason and does not alter analysis, persistence, deletion, or navigation behavior |
| task-20260708-manual-task-toolbar-save | `input/改善要望_20260705_操作体験の向上.md` | implemented_pending_ios_verification | gpt-5.4-mini | 手動タスク登録で保存/キャンセルが入力中でも見つけやすく、空タイトル保存は引き続き防止される | 2026-07-08: `ManualTaskView` のフォーム末尾の保存ボタンをナビゲーションバーの保存/キャンセルへ移し、保存可否判定を `canSave` に集約。GitHub CLI token が無効なためPR/Actions最新状態は未確認。`git diff --check` passed。Windows環境のため iOS build / SwiftUI表示確認は未実行 | 2026-07-08: available top-model static review passed; change is limited to ManualTaskView presentation and keeps task creation, document attachment, due date, and empty-title validation behavior unchanged |
| ci-20260627-ios-run-28207739501 | `https://github.com/ishiishikou/pribye/actions/runs/28207739501` | completed | gpt-5.5 | `build-test` の失敗原因を確認し、後続 run で解消済みなら完了扱いにする | 2026-06-27: 後続 iOS run `28241199526` が success、TestFlight run `28241501046` も success のため解消済みと判断 | resolved by later run `28241199526` |
| ci-20260627-ios-run-28233227662 | `https://github.com/ishiishikou/pribye/actions/runs/28233227662` | completed | gpt-5.5 | `build-test` の失敗原因を確認し、後続 run で解消済みなら完了扱いにする | 2026-06-27: 後続 iOS run `28241199526` が success、TestFlight run `28241501046` も success のため解消済みと判断 | resolved by later run `28241199526` |
| ci-20260627-ios-run-28240730883 | `https://github.com/ishiishikou/pribye/actions/runs/28240730883` | completed | gpt-5.5 | `build-test` の失敗原因を確認し、後続 run で解消済みなら完了扱いにする | 2026-06-27: 後続 iOS run `28241199526` が success、TestFlight run `28241501046` も success のため解消済みと判断 | resolved by later run `28241199526` |
| ci-20260624-ios-run-27874312688 | `https://github.com/ishiishikou/pribye/actions/runs/27874312688` | completed | gpt-5.5 | `build-test` の失敗原因を特定し、後続 run で再発なく成功する状態に戻す | job `82491148609` の失敗ログ確認と、後続 successful run `27874656339` の確認 | resolved by later run `27874656339`; failure was `ModelStateTests.testDocumentStatusSeparatesInternalAndUserLabels` expecting `解析中` but seeing `AI解析中` |
