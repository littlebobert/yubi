# TestFlight via GitHub Actions

Local **macOS / Xcode betas** are fine for development. App Store Connect rejects binaries built with beta toolchains, so TestFlight uploads run on a **stable Xcode** image in GitHub Actions (see `.github/workflows/testflight.yml`).

Signing is **manual**: Apple Distribution `.p12` + two App Store provisioning profiles (app + keyboard). Automatic/cloud signing is not used on the runner.

## One-time Apple setup

1. **App record** in [App Store Connect](https://appstoreconnect.apple.com) for `com.justin.yubi`.
2. **Identifiers**
   - App: `com.justin.yubi`
   - Keyboard: `com.justin.yubi.keyboard`
   - App Group: `group.com.justin.yubi`
3. **Apple Distribution certificate** → export from Keychain as **`.p12`** (cert + private key).
4. **App Store profiles** (type *App Store*, not Development), both including that Distribution cert:
   - Name **`Yubi`** → `com.justin.yubi`
   - Name **`Yubi Keyboard`** → `com.justin.yubi.keyboard`  
   Profile **names must match** exactly (including the space in `Yubi Keyboard`). Those names are hard-coded in `ci/ExportOptions.plist` and the Release signing settings.
5. **App Store Connect API key** (Admin or App Manager) for upload only — Key ID, Issuer ID, `.p8`.

## Add GitHub secrets

Repository → Settings → Secrets and variables → Actions.

### Already needed

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | API key id |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer UUID |
| `APP_STORE_CONNECT_API_KEY` | Full `.p8` PEM |
| `BUILD_CERTIFICATE_BASE64` | base64 of Distribution `.p12` |
| `BUILD_CERTIFICATE_PASSWORD` | `.p12` export password |

### New — provisioning profiles

On your Mac:

```bash
base64 -i ~/Downloads/Yubi.mobileprovision | pbcopy
# → paste into secret BUILD_PROVISION_PROFILE_BASE64

base64 -i ~/Downloads/Yubi_Keyboard.mobileprovision | pbcopy
# → paste into secret BUILD_PROVISION_PROFILE_KEYBOARD_BASE64
```

| Secret | File |
| --- | --- |
| `BUILD_PROVISION_PROFILE_BASE64` | `Yubi.mobileprovision` (main app) |
| `BUILD_PROVISION_PROFILE_KEYBOARD_BASE64` | `Yubi_Keyboard.mobileprovision` |

## Run a build

1. Commit/push the workflow + project signing settings if you have not already.
2. Actions → **TestFlight** → Run workflow  
   Optional: `marketing_version`, `xcode_version` (must stay non-beta).
3. Or push a tag: `v1.0.1`.

Build number = `github.run_number` (app + keyboard stay in sync).

## After upload

App Store Connect → TestFlight → wait for processing → assign testers.

## Local notes

- **Debug** still uses automatic signing for day-to-day device runs.
- **Release** in the Xcode project is manual (`Yubi` / `Yubi Keyboard`) for CI. Local Release archive needs those profiles installed (double-click the `.mobileprovision` files) or temporarily switch Release back to Automatic in Xcode.
- `FoundationModels` image `Attachment` is compile-gated off for stable CI Xcode; OpenAI/Claude image analysis is unchanged.
- Keyboard `WordFrequencies.json` is generated in a build phase (runner needs network once for `wordfreq`).
