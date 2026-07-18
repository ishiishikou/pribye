# TestFlight Upload 手順

このプロジェクトは GitHub Actions で build/test できる状態です。TestFlight へアップロードするには、配布用署名アセットを用意し、`TestFlight Upload` workflow を使います。

## 現在の識別子

- Team ID: `2QA6W85W3D`
- Bundle ID: `com.pribye.app`
- App Store Connect app record: 作成済み
- TestFlight upload workflow: `.github/workflows/testflight.yml`

## 重要な注意

- `.p12`、private key、provisioning profile、App Store Connect API key はリポジトリに commit しない。
- GitHub Actions secrets に登録する値は、チャットや issue に貼らない。
- `iOS` workflow と `TestFlight Upload` workflow はどちらも手動実行のみ。
- push だけでは GitHub Actions は起動しない。
- LiteRT-LM は `v0.14.0` を `GIT_LFS_SKIP_SMUDGE=1` で `Vendor/LiteRT-LM` へcloneし、XcodeGenからローカルSwift Packageとして参照する。
- このclone手順は、LiteRT-LMリポジトリ内のiOSでは不要なAndroid向けGit LFSオブジェクト欠落を回避するためのもの。上流のIssue #2407が解消したことを確認するまでは、通常のremote Swift Package参照へ戻さない。

## GitHub Actions secrets

Repository secrets に以下を登録する。

| Secret | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key の Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API の Issuer ID |
| `APP_STORE_CONNECT_API_KEY_P8` | API key の `.p8` ファイル全文 |
| `BUILD_CERTIFICATE_BASE64` | Apple Distribution certificate を含む `.p12` のBase64 |
| `P12_PASSWORD` | `.p12` export 時に設定したパスワード |
| `BUILD_PROVISION_PROFILE_BASE64` | App Store provisioning profile のBase64 |
| `KEYCHAIN_PASSWORD` | CI上の一時keychain用の任意の強いパスワード |

## 1. App Store Connect API key を作る

1. App Store Connect を開く。
2. Users and Access > Integrations > App Store Connect API に進む。
3. Team Keys で新しい key を作成する。
4. Access は `App Manager` を選ぶ。
5. 作成後に `.p8` をダウンロードする。`.p8` は再ダウンロードできないため、安全な場所に保管する。
6. 次の値を控える。
   - Key ID
   - Issuer ID
   - `.p8` ファイル全文

GitHub secrets への対応:

- Key ID → `APP_STORE_CONNECT_API_KEY_ID`
- Issuer ID → `APP_STORE_CONNECT_ISSUER_ID`
- `.p8` ファイル全文 → `APP_STORE_CONNECT_API_KEY_P8`

## 2. Apple Distribution certificate を `.p12` で用意する

Apple Developer で certificate を作るには CSR が必要です。Mac がない場合は、Windows上の OpenSSL で秘密鍵と CSR を作れます。

作業用フォルダを作り、その中で実行する。生成物は commit しない。

```powershell
openssl genrsa -out pribye_distribution.key 2048
openssl req -new -key pribye_distribution.key -out pribye_distribution.csr
```

Apple Developer 側:

1. Certificates, Identifiers & Profiles を開く。
2. Certificates > `+` に進む。
3. `Apple Distribution` を選ぶ。
4. `pribye_distribution.csr` をアップロードする。
5. 生成された certificate をダウンロードする。ここでは `distribution.cer` とする。

ダウンロード後、`.cer` と秘密鍵から `.p12` を作る。

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey pribye_distribution.key -in distribution.pem -out distribution.p12
```

`openssl pkcs12 -export` の途中で入力した export password を `P12_PASSWORD` として GitHub secrets に登録する。

`.p12` をBase64化する。

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12")) | Set-Content -NoNewline -Encoding ascii distribution.p12.base64.txt
```

`distribution.p12.base64.txt` の内容を `BUILD_CERTIFICATE_BASE64` に登録する。

## 3. App Store provisioning profile を作る

Apple Developer 側:

1. Certificates, Identifiers & Profiles を開く。
2. Profiles > `+` に進む。
3. Distribution の `App Store Connect` を選ぶ。
4. App ID は `com.pribye.app` を選ぶ。
5. Certificate は上で作成した Apple Distribution certificate を選ぶ。
6. profile name は分かりやすく `Pribye App Store` などにする。
7. `.mobileprovision` をダウンロードする。

`.mobileprovision` をBase64化する。

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Pribye_App_Store.mobileprovision")) | Set-Content -NoNewline -Encoding ascii Pribye_App_Store.mobileprovision.base64.txt
```

生成した `.base64.txt` の内容を `BUILD_PROVISION_PROFILE_BASE64` に登録する。

## 4. GitHub secrets を登録する

GitHub repository で Settings > Secrets and variables > Actions > Repository secrets に進み、必要な secrets を登録する。

`KEYCHAIN_PASSWORD` は Apple のパスワードではなく、CI上の一時keychainを開けるためだけの任意の強い文字列でよい。

登録後、ローカルや作業フォルダに残った次のファイルは安全に保管するか削除する。

- `*.p8`
- `*.key`
- `*.csr`
- `*.cer`
- `*.pem`
- `*.p12`
- `*.mobileprovision`
- `*.base64.txt`

## 5. TestFlight upload workflow を実行する

1. `.github/workflows/testflight.yml` が GitHub 上の対象ブランチに存在することを確認する。
2. GitHub repository の Actions を開く。
3. `TestFlight Upload` workflow を選ぶ。
4. `Run workflow` を押す。
5. 必要なら `build_number` を指定する。空欄なら GitHub run number が使われる。
6. 成功後、App Store Connect > TestFlight に build が表示されるまで待つ。

## 失敗時に見る場所

- secrets 未登録: `Validate secrets`
- LiteRT-LMのcloneまたはタグ取得失敗: `Clone LiteRT-LM without Git LFS binaries`
- certificate / password 不一致: `Install signing assets`
- provisioning profile と Bundle ID 不一致: `Archive`
- export option や署名設定の不一致: `Export IPA`
- API key 権限や App Store Connect 側の問題: `Upload to App Store Connect`
