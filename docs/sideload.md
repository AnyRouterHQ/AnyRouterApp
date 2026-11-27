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

## Running Inkling 2 Mini on a 12 GB iPhone

Inkling 2 Mini (1-bit) is a 6.9 GB file. How it runs depends on what the signing keeps. Settings › Diagnostics shows each fact for the installed build, so read it there rather than trusting this table.

| Signing | Memory limit | Address space | What the fit check plans for Inkling |
|---|---|---|---|
| Free Apple ID (Sideloadly, AltStore, SideStore) | Standard, about 3.5 GB (read on an iPhone 18 Pro). Some tools keep the increased limit, SideStore drops it. | Standard, about 7.4 GiB (computed from the kernel source, not measured) | Streamed from storage: CPU only, 4,096-token context. Not Available if the file is bigger than the largest file it can open. |
| Paid team: Xcode, or a re-signer that keeps the entitlements of the `AnyRouter-debug-adhoc` IPA | Increased, about 8 GB | Extended | In memory, 8,192-token context, very little room to spare |
| TestFlight | Increased | Extended | Same as a paid team |

The streamed tier is the likely one for a sideloaded build. It was measured only on the Simulator so far: 144 s to load and give the first token, 0.3 tokens per second (model-smoke run 46017297401).

Steps:

1. Install the newest **Device IPA** build: `AnyRouter-debug-unsigned` for a free Apple ID, `AnyRouter-debug-adhoc` for a paid team whose tool keeps entitlements.
2. Open Settings › Diagnostics and note: Installed RAM, Memory limit, Increased memory limit, Extended address space, Largest file it can open, and the Inkling line under Large models on this device.
3. If Inkling is offered, open Settings › Local Models, pick Inkling 2 Mini 26B (1-bit) and download it on Wi-Fi. It needs about 7.9 GB free (the file plus 1 GB to spare). The download goes on in the background and resumes after a drop.
4. Start a chat with Inkling and send "What is 2+2? Answer with one number." Expect minutes before the first word.
5. Back in Settings › Diagnostics, open the newest **Model load** record. It lists each step with its time and the app's memory: started, mapped (with how it runs), context ready, first token, finished (with tokens per second), or failed with the reason llama.cpp gave. If iOS closed the app, the record ends with "Ended after <step>".
6. A day later, Times iOS ended the app shows whether iOS ended it for memory.

Send back the step 2 values, the Model load record, and any line under Times iOS ended the app.

## Extensions in the IPA

The IPA carries the Control Center and Lock Screen controls as an embedded extension (`dev.anyrouter.app.controls`, in `AnyRouter.app/PlugIns`). Sideloadly and AltStore re-sign every embedded extension with your Apple ID. Each extension takes one more App ID from the free-account limit, so install it once and renew it, rather than reinstalling. The controls need no App Group: their intents open the app and run there. Add them from Control Center (Edit, Add a Control, AnyRouter) or the Lock Screen.

The IPA also carries the share extension "Ask AnyRouter" (`dev.anyrouter.app.share`). It hands images and PDFs to the app through the App Group `group.dev.anyrouter.app`. The CI build is unsigned and carries no entitlements, so whether the group exists is up to your signing tool. Apple lists App Groups as available to free accounts, but Sideloadly and AltStore may drop or rename the group. When the group is missing the extension still sends **text and links up to 1,500 characters** to the app through an `anyrouter://` link; images and PDFs show a message instead, and you attach them in the app with + (Photos, Files). The TestFlight build has the group.

## Running Inkling 2 Mini on a 12 GB iPhone

Inkling 2 Mini (1-bit, 6.88 GB) is bigger than an app may use, so how it runs depends on the signing:

| Install | Memory limit | How Inkling runs |
|---|---|---|
| `AnyRouter-debug-unsigned` signed with a free Apple ID | standard (about 3.5 GB on a 12 GB iPhone) | streams from storage: CPU only, 4,096-token context, slow |
| `AnyRouter-debug-adhoc` re-signed by a paid team that keeps entitlements, or TestFlight | increased (about 8 GB) | in memory, 8,192-token context |

Either way the file must also fit the largest file the app can open at once. If that is under 6.9 GB, Inkling shows as Not Available with that reason. These tiers come from the app's fit check; a phone has not run them yet.

1. Install the newest **Device IPA** build. The ad-hoc IPA's run summary lists the entitlements it carries.
2. Open Settings › Diagnostics and take a screenshot of the Memory section and **Large models on this device**: installed RAM, memory limit, both entitlements, the largest file it can open, and what the fit check says for Inkling.
3. Settings › Local Models › Inkling 2 Mini › Get. It needs about 7.9 GB free. The download goes on in the background and is checked against its sha256.
4. Start a chat with Inkling and send "What is 2+2? Answer with one number." The first token can take minutes (144 s on the CI Simulator, then 0.3 tokens a second).
5. Whether it answers or the app closes, open Settings › Diagnostics again. The **Model load** report lists each step with its time and memory: started, mapped, context ready, first token, finished with tokens per second. A report that ends before finished means iOS closed the app at that step.
6. A day later, **Times iOS ended the app** shows the exit counts iOS reported, such as Memory resource limit.

Send the screenshots of steps 2, 5 and 6 back.
