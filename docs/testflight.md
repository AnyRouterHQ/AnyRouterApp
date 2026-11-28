# Ship AnyRouter to TestFlight

CI uploads internal TestFlight builds. Xcode creates the certificate, App ID and profile itself through an App Store Connect API key, so no signing files go in the repo or in secrets.

## 1. App Store Connect (once)

1. In App Store Connect, Apps, New App: platform iOS, name **AnyRouter**, bundle ID `oneni.anyr.app` (register it under Identifiers first if it is not listed), any SKU.
2. Users and Access, Integrations, App Store Connect API, create a key with role **App Manager**. Download the `.p8` once and note the Key ID and Issuer ID.
3. The app uses the entitlement `com.apple.developer.kernel.increased-memory-limit`. With automatic signing and this key, Xcode enables the Increased Memory Limit capability on the App ID when it builds. If the archive step fails on it, enable the capability by hand on the App ID.
4. The app embeds two extensions, `oneni.anyr.app.controls` (Control Center controls) and `oneni.anyr.app.share` (share sheet), and an App Group `group.oneni.anyr.app` shared by the app and the share extension. With automatic signing and the key above, Xcode registers the two App IDs and the group on the first archive. If the archive fails on them, register the group under Identifiers, App Groups, and enable App Groups on `oneni.anyr.app` and `oneni.anyr.app.share` by hand.

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

## 5. Apple Intelligence on Private Cloud Compute (optional, off)

The picker has "Apple Intelligence (Cloud)": Apple's server model, the same Foundation Models API as the on-device one, with a 32K context and no API key. It works only when all of these hold:

1. **The account has the entitlement.** Apple grants `com.apple.developer.private-cloud-compute` on request to developers in the App Store Small Business Program with fewer than 2 million first-time downloads ([eligibility](https://developer.apple.com/private-cloud-compute/), [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute)). The operator applies from that page.
2. **The App ID has the capability.** In Certificates, Identifiers & Profiles, turn on Private Cloud Compute for `oneni.anyr.app`, then regenerate the provisioning profile used by the TestFlight workflow.
3. **The build carries the key.** Set `AR_PCC_ENTITLEMENT = YES` (in `Config/Local.xcconfig` locally, or as `AR_PCC_ENTITLEMENT=YES` on the TestFlight build). It picks `App/AnyRouter-PCC.entitlements` instead of `App/AnyRouter.entitlements`. Leave it `NO` until steps 1 and 2 are done: a key the App ID lacks breaks signing.
4. **The build uses the iOS 27 SDK, and the phone runs iOS 27.** The code that names the server model compiles only against the iOS 27 SDK (`APPLE_PCC_SDK`). The IPA and TestFlight builds still use Xcode 26, so today the row says "Needs iOS 27". Moving them to Xcode 27 changes the linked-on-or-after behaviour of the whole app, so it waits for step 1 (PLAN.md). The `ios27-build` workflow compiles the app with Xcode 27 on every push so this code keeps building.

Without the key, the row sits under Not available with "This build is not yet allowed to use Private Cloud Compute".
