# Ship AnyRouter to TestFlight

Milestone 1 is an internal TestFlight build uploaded by CI. Xcode creates the certificate, App ID and profile itself through an App Store Connect API key, so no signing files go in the repo or in secrets.

## 1. App Store Connect (once)

1. In App Store Connect, Apps, New App: platform iOS, name **AnyRouter**, bundle ID `dev.anyrouter.app` (register it under Identifiers first if it is not listed), any SKU.
2. Users and Access, Integrations, App Store Connect API, create a key with role **App Manager**. Download the `.p8` once and note the Key ID and Issuer ID.
3. The app uses the entitlement `com.apple.developer.kernel.increased-memory-limit`. With automatic signing and this key, Xcode enables the Increased Memory Limit capability on the App ID when it builds. If the archive step fails on it, enable the capability by hand on the App ID.

4. The app embeds two extensions, `dev.anyrouter.app.controls` (Control Center controls) and `dev.anyrouter.app.share` (share sheet), and an App Group `group.dev.anyrouter.app` shared by the app and the share extension. With automatic signing and the key above, Xcode registers the two App IDs and the group on the first archive. If the archive fails on them, register the group under Identifiers, App Groups, and enable App Groups on `dev.anyrouter.app` and `dev.anyrouter.app.share` by hand.

## 2. Repository secrets

```bash
gh secret set APPLE_TEAM_ID --body "<your team id>"
gh secret set ASC_KEY_ID --body "<key id>"
gh secret set ASC_ISSUER_ID --body "<issuer id>"
base64 -i AuthKey_XXXXXX.p8 | gh secret set ASC_KEY_P8_BASE64
```

Never commit these values. If any secret is missing, the workflow skips and lists what is missing in the job summary.

## 3. Run the workflow

Run **TestFlight** from the Actions tab (`workflow_dispatch`), or push a tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The build number is the workflow run number, so every upload is unique. The job archives, uploads straight to App Store Connect, and keeps the dSYMs as an artifact. `ITSAppUsesNonExemptEncryption` is set to NO, so there is no export-compliance prompt.

## 4. Install

1. In App Store Connect, Users and Access, add yourself (or any teammate) with a role that allows TestFlight. Then in the app's TestFlight tab, create an **Internal Testing** group and add the person.
2. Wait for the build to finish processing (a few minutes), then add it to the group.
3. Install the **TestFlight** app on the iPhone or iPad, sign in with the same Apple ID, and install AnyRouter.
