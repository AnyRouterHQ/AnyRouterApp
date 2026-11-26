# Install AnyRouter on your device (ad-hoc)

Milestone 1 ships as an ad-hoc IPA signed by CI. Only devices registered in the provisioning profile can install it (up to 100 per year per device type).

## 1. Apple Developer setup (once)

1. Register each device UDID under Certificates, Identifiers & Profiles, Devices. Find a UDID in Finder (select the device, click the model line under its name) or Apple Configurator 2.
2. Create the App ID `dev.anyrouter.app` and enable the capability **Increased Memory Limit** (entitlement `com.apple.developer.kernel.increased-memory-limit`). The app asks for this entitlement for large local models; a profile without it is rejected by CI.
3. Create an **Apple Distribution** certificate and export it from Keychain Access as a `.p12` with a password.
4. Create an **Ad Hoc** provisioning profile for `dev.anyrouter.app`, select the certificate and all devices, and download it. Regenerate it whenever you add a device.

## 2. Repository secrets

```bash
gh secret set APPLE_TEAM_ID --body "<your team id>"
base64 -i distribution.p12 | gh secret set IOS_CERT_P12_BASE64
gh secret set IOS_CERT_PASSWORD
base64 -i AnyRouter_AdHoc.mobileprovision | gh secret set IOS_ADHOC_PROFILE_BASE64
```

Never commit these files. If any secret is missing, the workflow skips and says which one in the job summary.

## 3. Build

Run **Release (ad-hoc)** from the Actions tab (`workflow_dispatch`), or push a tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The job uploads `AnyRouter-adhoc` (IPA and dSYMs) as an artifact, prints the IPA size in the job summary, and on tags attaches the IPA to the GitHub release.

## 4. Install without Xcode

**Apple Configurator 2 (Mac):** connect the device, open Apple Configurator 2, drag `AnyRouter.ipa` onto the device.

**Over the air:** host the IPA and a `manifest.plist` on an HTTPS server, then open `itms-services://?action=download-manifest&url=https://HOST/manifest.plist` in Safari on the device.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>items</key><array><dict>
    <key>assets</key><array><dict>
      <key>kind</key><string>software-package</string>
      <key>url</key><string>https://HOST/AnyRouter.ipa</string>
    </dict></array>
    <key>metadata</key><dict>
      <key>bundle-identifier</key><string>dev.anyrouter.app</string>
      <key>bundle-version</key><string>1.0</string>
      <key>kind</key><string>software</string>
      <key>title</key><string>AnyRouter</string>
    </dict>
  </dict></array>
</dict></plist>
```

Replace `HOST` with your server. If iOS asks, enable Developer Mode in Settings, Privacy & Security.
