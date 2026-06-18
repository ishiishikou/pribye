# プリバイ（プリントばいばい）UI設計

---

# 1. UIコンセプト

## アプリUI思想
「情報を保持するアプリ」ではなく、「意思決定を削るアプリ」。

ユーザーの行動は以下に最短化される：

撮影 → 補正 → 自動抽出 → 確認 → タスク完了

UIは管理ではなく「処理済みタスク表示」に特化する。

---

## 中核体験
- プリントは入力データ
- タスクが主役
- OCR/画像は裏側情報
- ユーザーは結果のみ扱う

---

## UI判断方針
- Apple標準UI優先
- 情報量を削減
- 操作導線を短縮
- 認知負荷最小化

---

## 参考アプリ
- Apple Reminders（タスク構造）
- Apple Photos（撮影→閲覧体験）
- Notion（構造化思想）
- Google Keep（軽量入力）

---

# 2. デザインシステム

## Color
- Primary: systemBlue
- Secondary: systemIndigo
- Background: systemBackground
- Surface: secondarySystemBackground
- Text: label
- SubText: secondaryLabel
- Error: systemRed
- Success: systemGreen

---

## Typography
- Title: largeTitle / bold
- Heading: title2
- Body: body
- Caption: caption1

---

## Spacing
- Base grid: 4pt
- Standard margin: 16pt
- Section spacing: 24pt
- Card padding: 12–16pt

---

## Components

### Card
- タスク・プリント表示
- 境界線なし（背景差分）

### Button
- Primary: filled
- Secondary: border
- Destructive: red

### List Item
- 左：情報
- 右：状態
- swipe操作対応

### Empty State
- テキスト + CTAのみ

### Loading State
- skeleton UI
- 進捗バーなし

---

# 3. 情報設計

## 画面一覧
- ホーム（タスク一覧）
- 撮影
- 補正
- プリント詳細
- タスク詳細
- 設定

---

## 階層構造

ホーム
 ├─ 撮影
 │   ├─ 補正
 │   └─ AI処理
 ├─ プリント詳細
 ├─ タスク詳細
 └─ 設定

---

## Navigation
- Tab構成
  - タスク
  - プリント
  - 撮影（中心アクション）

---

## モーダル
- 撮影
- 補正
- タスク編集
- カレンダー登録確認

---

## 主要フロー

撮影 → 補正 → OCR → タスク生成 → 表示
タスク → 完了
タスク → プリント確認 → OCRハイライト

---

# 4. 各画面仕様

---

## ホーム（タスク）

目的：日常タスク管理

表示：
- タスク名
- 期限
- 完了状態

状態：
- 空：撮影CTA
- 通常：リスト

UX注意：
- 分類なし
- ソート固定（期限優先）

---

## 撮影

目的：プリント入力

構成：
- カメラ全画面
- シャッター
- プレビュー

UX：
- 即撮影可能
- 設定なし

---

## 補正

目的：OCR精度向上

構成：
- 上：拡大編集
- 下：全体画像

操作：
- 四隅ドラッグ
- 自動補正

---

## プリント詳細

目的：AI結果確認

構成：
- タスク一覧
- 元画像サムネイル
- OCRハイライト

---

## タスク詳細

目的：行動管理

構成：
- タスク
- 期限
- 完了ボタン
- カレンダー登録

---

# 5. ワイヤーフレーム

## ホーム
--------------------------------
Navigation

今日

タスクリスト
- 体操服を持参
- 6/20期限

＋（撮影）

Tab
--------------------------------

---

## 撮影
--------------------------------
カメラビュー

シャッター

プレビュー → 次へ
--------------------------------

---

## プリント詳細
--------------------------------
プリント名

タスク一覧
- 体操服を持参

元画像
--------------------------------

---

# 6. SwiftUI設計

## コンポーネント
- NavigationStack
- TabView
- List
- Sheet
- CameraView
- CropView

---

## View構成
- HomeView
- TaskListView
- TaskRowView
- CameraView
- CropView
- DocumentDetailView
- TaskDetailView

---

## State管理
- DocumentStore
- TaskStore
- OCRState
- CameraState

---

## データ
- SwiftData / CoreData
- Document → Task構造

---

# 7. UX改善提案

## 提案1
撮影後のシームレス遷移

理由：操作分断削減
影響：フロー短縮

---

## 提案2
完了タスクを薄化表示

理由：履歴保持
メリット：安心感

---

## 提案3
AI結果の信頼段階UI

理由：確認コスト削減
影響：詳細画面のみ表示

---

## 提案4
撮影FAB固定

理由：導線短縮
メリット：習慣化