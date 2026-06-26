# TestFlight Setup Guide

This guide walks through setting up GitHub Secrets so the `testflight.yml` workflow can
build, sign, and upload your Look iOS app to TestFlight on every push to `main` or tagged release.

---

## Prerequisites

- **Apple Developer account** ($99/year)
- **App Store Connect app record** for Look (bundle ID: `com.sladebot.look`)
- **Admin access** to the GitHub repo `sladebot/look`

---

## Step 1: Create App Store Connect API Key

1. Go to [App Store Connect → Users and Access → Keys](https://appstoreconnect.apple.com/access/api)
2. Click **+** to generate a new key
3. Name: `GitHub Actions`
4. Access: **App Manager** (needed for upload + TestFlight submission)
5. Download the `.p8` file — **save it securely, you can only download it once**

Record these values (shown on the Keys page):
- **Key ID** — e.g. `ABC1234567`
- **Issuer ID** — e.g. `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

---

## Step 2: Export Signing Certificate as .p12

You need a valid **iOS Distribution** certificate. If you don't have one:

```bash
# Generate a new distribution certificate
# In Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority
# Upload the CSR to developer.apple.com → Certificates → iOS Distribution
```

Once you have the certificate in Keychain Access:

```bash
# Export as .p12
security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t certs \
  -f pkcs12 \
  -o ~/Desktop/distribution.p12
```

You'll be prompted for:
- **Export password** (create one — this becomes `P12_PASSWORD` secret)
- **Keychain password** (your Mac login password)

Convert the .p12 to base64:

```bash
base64 -i ~/Desktop/distribution.p12 -o ~/Desktop/distribution.p12.b64
```

---

## Step 3: Download Provisioning Profile

1. Go to [developer.apple.com → Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Create an **iOS App Store Distribution** profile for `com.sladebot.look`
3. Download the `.mobileprovision` file
4. Convert to base64:

```bash
base64 -i ~/Downloads/Look_Distribution.mobileprovision -o ~/Desktop/profile.b64
```

---

## Step 4: Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value | Source |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Contents of `distribution.p12.b64` | Step 2 |
| `P12_PASSWORD` | Password you set when exporting .p12 | Step 2 |
| `BUILD_PROVISION_PROFILE_BASE64` | Contents of `profile.b64` | Step 3 |
| `KEYCHAIN_PASSWORD` | Any temporary password value you create locally | Create new |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from App Store Connect | Step 1 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from App Store Connect | Step 1 |
| `APP_STORE_CONNECT_API_KEY` | Raw contents of the `.p8` file | Step 1 |

---

## Step 5: Trigger the Build

The workflow runs automatically on:

- **Push to `main`** (when `ios/**` files change)
- **Tag push** (e.g. `git tag v1.0.0 && git push --tags`)
- **Manual trigger** (`Actions → Deploy to TestFlight → Run workflow`)

---

## How It Works

```
Checkout → xcodegen → Setup Signing → Bump Build → Archive → Export IPA → Upload to TestFlight
```

1. **Code signing**: The workflow creates a temporary keychain, imports your `.p12` certificate
   and `.mobileprovision` profile from GitHub Secrets
2. **Build number**: Auto-incremented on each run (`CURRENT_PROJECT_VERSION` in `project.yml`)
3. **Archive + Export**: `xcodebuild archive` → `xcodebuild -exportArchive` produces a signed `.ipa`
4. **Upload**: `xcrun altool --upload-app` sends the IPA to App Store Connect
5. The IPA is also saved as a 90-day GitHub Artifact

---

## Troubleshooting

**"No signing certificate found"**
→ Your `.p12` is expired or doesn't include the private key. Re-export from Keychain Access.

**"Provisioning profile doesn't include signing certificate"**
→ Go to developer.apple.com → Profiles → Edit → make sure your Distribution cert is checked.

**"App record not found"**
→ Create the app in App Store Connect first: **My Apps → + → New App** with bundle ID `com.sladebot.look`.

**"Authentication error"**
→ Verify the API Key has **App Manager** access in App Store Connect.
