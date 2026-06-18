# App Store公開前チェックリスト

- Apple Developer Programに登録する。
- Bundle ID `com.pribye.app` をApple Developerで作成する。
- `project.yml` の `DEVELOPMENT_TEAM` を設定する。
- App Store Connectでアプリ、SKU、カテゴリ、年齢制限を登録する。
- Camera、Photos、Calendarの権限文言を実機で確認する。
- Privacy Nutrition Labelで写真、カレンダー、広告SDKの扱いを申告する。
- 広告SDKを入れる場合は非パーソナライズ設定を既定にし、プリント画像・OCR・タスク内容を渡していないことを確認する。
- 課金で広告非表示にする場合はStoreKit商品IDを作成し、Sandbox購入テストを行う。
- TestFlightで撮影、補正、OCR、AI抽出、タスク完了、カレンダー登録、CSVエクスポートを確認する。
