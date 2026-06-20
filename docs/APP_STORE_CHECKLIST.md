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
- App Store Connect app record: done.
- Set app name, SKU, primary category, age rating, and availability.
- Prepare screenshots, description, keywords, support URL, and privacy policy URL.
- Complete Privacy Nutrition Label using `docs/APP_PRIVACY.md` as the current implementation memo.

## TestFlight
- Archive and upload the first build.
- Prepare distribution signing for CI or use Xcode Organizer on a Mac.
- If using CI upload, create an App Store Connect API key and store signing assets in GitHub Actions secrets.
- Verify VisionKit multi-page document scanning, page switching during correction, OCR, page-scoped task extraction, task completion, calendar registration, and CSV export.
- Verify permission prompts for Camera, Photos, and Calendar on a real device.
- Verify Foundation Models integration and Apple Intelligence unavailable guidance using `docs/FOUNDATION_MODELS_SETUP.md`.

## Privacy / Ads / Purchases
- Do not send print images, OCR text, or extracted task content to external AI APIs.
- Current build privacy declaration memo: `docs/APP_PRIVACY.md`.
- If an ad SDK is added, keep print images, OCR text, task titles, and extracted content out of ad SDK payloads.
- StoreKit ad removal code uses `com.pribye.remove_ads`; create that product in App Store Connect using `docs/STOREKIT_SETUP.md` and test sandbox purchases.
- AdMob integration uses Google test IDs by default; replace them using `docs/ADMOB_SETUP.md` before App Store submission.
- Complete App Store privacy answers after reviewing Google Mobile Ads SDK data disclosure in `docs/APP_PRIVACY.md`.
