# App Privacy Declaration

この文書は、現在のプリバイ実装を前提にした App Store Connect のプライバシー申告メモです。Google Mobile Ads SDK（AdMob）を採用しているため、広告SDKのデータ利用を含めて提出前に必ず見直します。

## 現在の実装方針

- プリント画像、補正後画像、OCR全文、OCR座標、抽出タスク、CSVデータは外部サーバーへ送信しない。
- OCRとタスク抽出は端末内処理を前提にする。
- 補正後画像はユーザー端末の写真ライブラリに保存する。
- カレンダー登録はユーザー操作時のみ EventKit で端末のカレンダーへ追加する。
- CSVエクスポートはユーザーが共有先を選んだ場合のみ共有シートへ渡す。
- 広告SDKとして Google Mobile Ads SDK を導入済み。
- 分析SDK、クラッシュレポートSDKは現在未導入。
- 広告非表示課金は StoreKit 2 を使い、購入処理は Apple の標準フローに委ねる。

## App Store Connect 申告案

現在のビルドでは Google Mobile Ads SDK がデータを収集し得るため、`Data Not Collected` のまま提出しない。

プリバイ固有データの扱い:

- Camera / Photos は端末内の撮影、選択、保存、表示にのみ使う。
- Calendar はユーザーが明示的に押したタスク登録にのみ使う。
- OCR全文やタスク名は SwiftData にローカル保存され、外部送信しない。
- CSVはユーザー開始のエクスポートであり、アプリ開発者が収集しない。
- 広告リクエストへプリント画像、OCR全文、タスク名、抽出内容、CSVデータを渡さない。

AdMobについては Google の App Store data disclosure を確認し、少なくとも次のカテゴリを App Store Connect で再評価する:

- Location（IPアドレスによる概略位置）
- Identifiers（広告IDなど）
- Usage Data / Advertising Data
- Diagnostics
- User Interaction / Performance Data

Google公式メモ: https://developers.google.com/admob/ios/privacy/data-disclosure

## 権限説明

`Info.plist` で利用している説明:

- `NSCameraUsageDescription`: プリントを撮影してタスク化するため。
- `NSPhotoLibraryAddUsageDescription`: 補正後のプリント画像を写真ライブラリへ保存するため。
- `NSPhotoLibraryUsageDescription`: 保存済みの補正後画像を確認し、OCR根拠を表示するため。
- `NSCalendarsFullAccessUsageDescription`: 選択したタスクをカレンダーへ登録するため。

## AdMob

AdMob設定手順は `docs/ADMOB_SETUP.md` に記載する。

広告SDKへ渡してはいけない情報:

- プリント画像
- 補正後画像
- OCR全文
- OCR座標
- タスク名
- 抽出内容
- CSVデータ

## 提出前確認

- App Store Connect の privacy answers がこの文書と一致している。
- `docs/ADMOB_SETUP.md` に沿って本番AdMob App ID / ad unit IDへ差し替えている。
- Google Mobile Ads SDK の最新 App Store data disclosure を確認している。
- 外部AI APIへ画像、OCR、タスクを送るコードがない。
- TestFlight実機確認で権限プロンプトの文言が用途と一致している。
