# TestFlight via GitHub Actions

Local **macOS / Xcode betas** are fine for development. App Store Connect rejects binaries built with beta toolchains, so TestFlight uploads run on a **stable Xcode** image in GitHub Actions (see `.github/workflows/testflight.yml`).

## One-time Apple setup

1. **App record** in [App Store Connect](https://appstoreconnect.apple.com) for `com.justin.yubi` (if it does not already exist).
2. **Identifiers** in the Apple Developer portal (usually already created by Xcode automatic signing):
   - App: `com.justin.yubi`
   - Keyboard: `com.justin.yubi.keyboard`
   - App Group: `group.com.justin.yubi`
   - Shared keychain group capability as in the entitlements
3. **Apple Distribution certificate**
   - Developer portal → Certificates → Apple Distribution
   - Export from Keychain Access as a `.p8` is *not* enough for signing — export the cert + private key as a **.p12**
4. **App Store Connect API key**  
   Users and Access → Integrations → App Store Connect API → Generate (role **Admin** or **App Manager**).  
   Download the `.p8` once; note **Key ID** and **Issuer ID**.  
   The workflow uses automatic signing with this key (`-allowProvisioningUpdates`), so Xcode on the runner will create or refresh App Store profiles for the app and keyboard when needed.

## GitHub secrets

Repository → Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | API key id (e.g. `ABC1234DEF`) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer UUID from the API keys page |
| `APP_STORE_CONNECT_API_KEY` | Full contents of `AuthKey_….p8` (including `-----BEGIN PRIVATE KEY-----`) |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i Certificates.p12 \| pbcopy` (Distribution .p12) |
| `BUILD_CERTIFICATE_PASSWORD` | Password you set when exporting the .p12 |

Encode the certificate from a Mac:

```bash
base64 -i AppleDistribution.p12 | pbcopy
```

## Run a build

**Manual:** Actions → **TestFlight** → Run workflow  
Optional inputs:

- `marketing_version` — e.g. `1.0.1` (otherwise uses the project `MARKETING_VERSION`)
- `xcode_version` — defaults to `latest-stable` (must remain a **non-beta** Xcode)

**Tag:** push `v1.0.1` (or any `v*`) to trigger the same workflow.

Build number is `github.run_number` and is applied to **both** the app and keyboard targets so they stay in sync.

## After upload

1. App Store Connect → your app → TestFlight  
2. Wait until processing finishes (email / status)  
3. Assign the build to internal or external testers  

Encryption: `Yubi/Info.plist` already sets `ITSAppUsesNonExemptEncryption` to `false`.

## If the upload is rejected for SDK / Xcode

Apple periodically bumps the minimum iOS SDK for new uploads. This workflow pins **stable** Xcode on `macos-15`. If validation complains about an old SDK:

1. Re-run with a newer `xcode_version` (e.g. `16.4`, or whatever release image provides the required SDK).  
2. Or bump `runs-on` when GitHub publishes a newer macOS image that includes the required release Xcode.

Do **not** point this workflow at an Xcode **beta** — that is the problem you are avoiding by not archiving on your local macOS beta.

## Local notes

- `FoundationModels` (Apple Intelligence backend) is compiled only when the SDK provides it (`canImport`). Builds from stable Xcode still ship OpenAI / Claude; on-device Apple analysis is simply unavailable until a release SDK includes those APIs.  
- Keyboard lexicon `WordFrequencies.json` is generated in the Xcode build phase (needs network once for `wordfreq` on the runner).
