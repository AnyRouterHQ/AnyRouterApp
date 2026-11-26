# Sideload a debug build

CI builds an unsigned debug IPA you can install on your own iPhone or iPad with Sideloadly or AltStore. They re-sign it with your Apple ID. No paid developer account is needed.

## Get the IPA

1. Open the **Device IPA** workflow in the Actions tab. It runs on every push to `main`, or press **Run workflow**.
2. Open a green run and download the artifact **AnyRouter-debug-unsigned** (kept 14 days). Unzip it to get `AnyRouter-debug-unsigned.ipa`.

Or with the CLI: `gh run download --name AnyRouter-debug-unsigned`.

## Install

- **Sideloadly**: connect the device, drag the IPA in, enter your Apple ID, press Start. Trust the developer profile in Settings, General, VPN & Device Management.
- **AltStore**: add the IPA from the My Apps tab (or share it to AltStore from Files).

## Limits of a free Apple ID

- The install expires after **7 days**. Re-install to renew (AltStore can refresh in the background).
- The increased-memory-limit entitlement is dropped when signing with a free account. Large models can run out of memory: **0.6B to 1.7B models are fine, 4B models may crash**.
- Apple Foundation Models needs Apple Intelligence turned on and iOS 26.
- Free accounts allow only a few active app IDs; remove old sideloaded apps if the install is refused.

## Extensions in the IPA

The IPA carries the Control Center and Lock Screen controls as an embedded extension (`dev.anyrouter.app.controls`, in `AnyRouter.app/PlugIns`). Sideloadly and AltStore re-sign every embedded extension with your Apple ID. Each extension takes one more App ID from the free-account limit, so install it once and renew it, rather than reinstalling. The controls need no App Group: their intents open the app and run there. Add them from Control Center (Edit, Add a Control, AnyRouter) or the Lock Screen.

The IPA also carries the share extension "Ask AnyRouter" (`dev.anyrouter.app.share`). It hands images and PDFs to the app through the App Group `group.dev.anyrouter.app`. The CI build is unsigned and carries no entitlements, so whether the group exists is up to your signing tool. Apple lists App Groups as available to free accounts, but Sideloadly and AltStore may drop or rename the group. When the group is missing the extension still sends **text and links up to 1,500 characters** to the app through an `anyrouter://` link; images and PDFs show a message instead, and you attach them in the app with + (Photos, Files). The TestFlight build has the group.
