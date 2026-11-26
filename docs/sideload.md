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
