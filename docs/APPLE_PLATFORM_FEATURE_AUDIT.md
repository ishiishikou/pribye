# Apple標準機能の採用メモ

プリバイで、独自実装よりApple標準機能を使った方がよい箇所の棚卸しです。

## 採用済み・今回採用

- 書類撮影: `VisionKit` の `VNDocumentCameraViewController` を採用。自動書類検出、撮影、台形補正は標準UIに任せる。
- 複数ページ書類スキャン: `VNDocumentCameraScan` から全ページを取り込み、1プリント内の複数 `Page` として保持する。
- VisionKitの四隅調整UIだけを独自UIへ差し替える公開APIはないため、VisionKit経路では標準UIだけを使う。
- ページ単位解析: AIタスク抽出は一括全文投入ではなく、対象ページ + 次ページ冒頭の文脈でページごとに実行する。
- 写真選択: `PhotosPicker` を継続。
- OCR: `Vision` の `VNRecognizeTextRequest` を継続。
- OCR補正・タスク抽出: `FoundationModels` が使える端末ではオンデバイスで実行し、外部AI APIへ画像/OCR/抽出結果を送らない。
- 予定登録: `EventKit` を継続。
- 課金: `StoreKit 2` を継続。
- データ保存: `SwiftData` を継続。

## 次に検討する価値があるもの

1. App Intents / App Shortcuts
   - 「今日の持ち物を見る」「未完了タスクを開く」などをSiri、ショートカット、Spotlightへ出せる。
   - App Store初期版では必須ではないが、タスク中心アプリとの相性はよい。

2. EventKitUI
   - カレンダー登録を標準のイベント編集画面に寄せられる。
   - 現状の自動登録より、ユーザーが通知やカレンダーを確認して保存できるメリットがある。

3. UserNotifications
   - アプリ内タスクの期限通知をローカル通知で出せる。
   - 通知許可、通知タイミング、広告非表示課金との関係を設計してから入れる。

## 今は採用しないもの

- iCloud同期 / CloudKit
  - 個人ローカル利用を優先する現設計では、初期版の範囲外。
- 外部AI API
  - プリント画像、OCR全文、抽出タスク内容を外部送信しない方針に反する。
- 独自の連続カメラ自動撮影
  - 書類検出と撮影はVisionKit標準UIに任せた方が安全で、保守範囲も小さい。
