# App Store / TestFlight Checklist

## Apple Developer
- Apple Developer Program approval: done.
- Team ID: `2QA6W85W3D`.
- Bundle ID target: `com.pribye.app`.
- Explicit App ID `com.pribye.app` in Apple Developer: done.
- Enable only the capabilities the app actually uses.

## Xcode Project
- `project.yml` sets `DEVELOPMENT_TEAM`.
- `PRODUCT_BUNDLE_IDENTIFIER` is `com.pribye.app`.
- `CODE_SIGN_STYLE` is `Automatic`.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set.
- CI build/test passes on GitHub Actions.

## App Store Connect
- Create the App Store Connect app record.
- Set app name, SKU, primary category, age rating, and availability.
- Prepare screenshots, description, keywords, support URL, and privacy policy URL.
- Complete Privacy Nutrition Label for Photos, Camera, Calendar, advertising, and analytics.

## TestFlight
- Archive and upload the first build.
- Verify camera capture, image review/correction, OCR, task extraction, task completion, calendar registration, and CSV export.
- Verify permission prompts for Camera, Photos, and Calendar on a real device.

## Privacy / Ads / Purchases
- Do not send print images, OCR text, or extracted task content to external AI APIs.
- If an ad SDK is added, keep print images, OCR text, task titles, and extracted content out of ad SDK payloads.
- If paid ad removal is added, create StoreKit product IDs and test sandbox purchases.
