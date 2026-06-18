# TestFlight Upload Plan

This project can already build and test in GitHub Actions. Uploading to TestFlight is a separate signed archive step.

## Current Identifiers
- Team ID: `2QA6W85W3D`
- Bundle ID: `com.pribye.app`
- App Store Connect app record: created

## Option A: Upload From Xcode On A Mac
Use this if you have access to a Mac with Xcode 26.

1. Pull the latest `main`.
2. Run `xcodegen generate`.
3. Open `Pribye.xcodeproj`.
4. Sign in to Xcode with the Apple Developer account.
5. Select the `Pribye` target and confirm:
   - Team: `2QA6W85W3D`
   - Bundle Identifier: `com.pribye.app`
   - Signing: Automatically manage signing
6. Product > Archive.
7. In Organizer, Distribute App > App Store Connect > Upload.

## Option B: Upload From GitHub Actions
Use this if there is no local Mac.

Required GitHub repository secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `BUILD_PROVISION_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`

Required Apple-side assets:

1. App Store Connect API key with App Manager access.
2. Apple Distribution certificate exported as `.p12`.
3. App Store provisioning profile for `com.pribye.app`.

After the secrets exist, add a manual `workflow_dispatch` archive workflow that imports the certificate/profile, runs `xcodebuild archive`, exports an `.ipa`, and uploads with `xcrun altool` or `xcrun notarytool`/Transporter tooling available in Xcode.
