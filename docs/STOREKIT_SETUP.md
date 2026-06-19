# StoreKit Setup

プリバイの広告非表示課金は StoreKit 2 の non-consumable product として実装しています。

## Product

| Item | Value |
| --- | --- |
| Type | Non-Consumable |
| Product ID | `com.pribye.remove_ads` |
| Reference Name | `Remove Ads` |
| App UI | 設定 > 広告 |

## App Store Connect

### 事前条件

- App Store Connect の `Agreements, Tax, and Banking` で Paid Apps agreement、税務、銀行口座の設定が有効になっている。
- App record `プリバイ` / Bundle ID `com.pribye.app` が作成済み。
- App Store Connect にログインできる Apple ID に、App Manager 以上の権限がある。
- Product ID は作成後に変更できない前提で扱う。必ず `com.pribye.remove_ads` を使う。

### 商品作成

1. App Store Connect で `My Apps` を開く。
2. `プリバイ` の app record を開く。
3. サイドバーまたは Features の `In-App Purchases` を開く。
4. `+` を押して新しい in-app purchase を作成する。
5. Type は `Non-Consumable` を選ぶ。
6. Product ID に `com.pribye.remove_ads` を入力する。
7. Reference Name は `Remove Ads` にする。
8. `Create` / `Save` で商品を作成する。

### 価格と販売状態

1. Pricing / Price Schedule で価格を設定する。
2. 販売地域は App 本体の提供地域に合わせる。
3. `Cleared for Sale` または同等の販売有効設定がある場合は有効にする。

価格は後から変更できるが、初回は低価格帯で始めるのが無難です。個人利用アプリなので、価格判断はリリース前にユーザーが確認してください。

### ローカライズ

日本語ローカライズを追加する。

| Field | Value |
| --- | --- |
| Display Name | `広告を非表示` |
| Description | `タスク一覧とプリント一覧の広告表示を非表示にします。` |

英語ローカライズが必要な場合の例:

| Field | Value |
| --- | --- |
| Display Name | `Remove Ads` |
| Description | `Removes ads from the task and print lists.` |

### Review Information

App Review 用の情報を入力する。

- Review Screenshot: 設定画面の広告セクションが分かるスクリーンショット。
- Review Notes: `Open Settings > Ads, then purchase "広告を非表示" to hide ads on the task and print lists.`

初回の in-app purchase は、App の新しいバージョン提出と一緒に審査へ出す必要がある場合があります。App Store Connect 上で商品ステータスが `Ready to Submit` のままなら、次の app version の submission にこの IAP を含めます。

### App側との対応

アプリ内コードは次の Product ID を読みに行く。

```swift
com.pribye.remove_ads
```

対応箇所:

- `Pribye/Services/PurchaseService.swift`
- `Pribye/Views/SettingsView.swift`
- `Pribye/Views/Components.swift`

Product ID を App Store Connect 側で別名にした場合、アプリ側も同時に変更しないと商品が表示されない。

## Sandbox Test

### Sandbox tester

1. App Store Connect の Users and Access を開く。
2. `Sandbox Testers` を開く。
3. 新しい sandbox tester を作成する。
4. 実機で App Store の sandbox 購入に使う。

### TestFlightで確認すること

確認すること:

- 商品が設定画面に価格付きで表示される。
- 購入成功後に `adsRemoved` が有効化され、タスク一覧/プリント一覧の広告枠が消える。
- アプリ再起動後も entitlement 復元で広告枠が消える。
- `購入を復元` で購入済み entitlement を復元できる。
- 未購入アカウントでは復元不可メッセージが表示される。
- ネットワーク不通時にクラッシュしない。
- App Store Connectの商品が未作成の場合、設定画面に「課金項目が見つかりません」と表示される。

### よくある失敗

| 症状 | 確認すること |
| --- | --- |
| 商品が表示されない | Product ID が `com.pribye.remove_ads` と一致しているか |
| 商品が表示されない | Paid Apps agreement / tax / banking が未完了ではないか |
| 商品が表示されない | IAP 商品が保存済みで、必要なローカライズと価格が入っているか |
| 購入できない | sandbox tester でサインインしているか |
| 復元できない | 同じ sandbox tester で過去に購入済みか |
| 審査へ出せない | 初回IAPを app version の submission に含めているか |

## Implementation Pointers

- Product ID: `Pribye/Services/PurchaseService.swift`
- Purchase UI: `Pribye/Views/SettingsView.swift`
- Ad visibility: `Pribye/Views/Components.swift`

## Notes

- App Store Connect の商品作成は外部状態なので、リポジトリだけでは完了できない。
- Product ID を変える場合は `PurchaseService.removeAdsProductID` とこの文書を同時に更新する。
- 広告SDKを更新・差し替えする場合は `docs/APP_PRIVACY.md` を見直す。
- IAP 商品を作成しても、pushしない限りGitHub Actionsは走らない。
