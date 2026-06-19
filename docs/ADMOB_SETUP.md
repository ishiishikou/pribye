# AdMob Setup

プリバイは広告SDKとして Google Mobile Ads SDK（AdMob）を採用します。

## Current Integration

- SDK: Google Mobile Ads SDK via Swift Package Manager
- Package URL: `https://github.com/googleads/swift-package-manager-google-mobile-ads.git`
- Version rule: from `13.5.0`
- Banner format: anchored adaptive banner
- Display locations: task list and print list only
- Hidden when `adsRemoved` entitlement is active

## Test IDs

現在の `project.yml` は Google 公式のテストIDを使っています。

| Setting | Value |
| --- | --- |
| `ADMOB_APP_ID` | `ca-app-pub-3940256099942544~1458002511` |
| `ADMOB_BANNER_AD_UNIT_ID` | `ca-app-pub-3940256099942544/2435281174` |

本番公開前に、AdMobで発行した実IDへ差し替える必要があります。

## Production Setup

1. AdMob account を作成する。
2. iOS app `com.pribye.app` を登録する。
3. App ID を取得し、`project.yml` の `ADMOB_APP_ID` を置き換える。
4. Banner ad unit を作成し、`ADMOB_BANNER_AD_UNIT_ID` を置き換える。
5. Google の最新 quick start にある `SKAdNetworkItems` を確認し、必要なら `Info.plist` を更新する。
6. TestFlightで広告表示、課金後の広告非表示、プライバシー申告を確認する。

## Privacy Boundary

広告SDKへ渡してはいけない情報:

- プリント画像
- 補正後画像
- OCR全文
- OCR座標
- タスク名
- 抽出内容
- CSVデータ

現在の実装では、広告リクエストにプリバイ固有の画像/OCR/タスクデータを渡していません。

## Official References

- Google Mobile Ads SDK quick start: https://developers.google.com/admob/ios/quick-start
- Banner ads: https://developers.google.com/admob/ios/banner
- Test ads: https://developers.google.com/admob/ios/test-ads
- App Store data disclosure: https://developers.google.com/admob/ios/privacy/data-disclosure
