# Model picker

The sheet opened from the model pill: search, sections for Apple Intelligence, AnyRouter (cloud) and On this device, a selected checkmark, fit badges for local models, and a sign-in prompt when signed out.

## Sub-features

- `picker-open` opens from the pill.
- `picker-search` filters by name.
- `picker-select` choosing a row closes the sheet and updates the pill.
- `picker-switch-mid-chat` the next message uses the newly chosen model.

## How to get to it (user POV)

- Tap the pill labeled `Model` in the chat toolbar (its accessibility value is the selected model name).

## Driving it with the journeys harness

Preconditions:

- Demo launch, signed in. The pill starts on `AnyRouter` (the router picks the model), so the sheet opens on the AnyRouter tab.

- **Open.** Tap `Model`. A segmented control with `Local` and `AnyRouter` appears.
- **Tabs.** Tap `Local`; it lists `model-row.apple/foundation`. Tap `AnyRouter`; the cloud rows (`model-row.anyrouter/<provider>/<model>`) show.
- **Filter and select.** Tap the search field `Search models`, type `sonnet`, tap `model-row.anyrouter/anthropic/claude-sonnet-4-6`. The sheet closes and `Model`'s value is `Claude Sonnet 4.6`.
- **Switch mid-conversation.** Send a message, reopen the picker, choose `Gemini 2.5 Pro`, send another. The reply shows a `switch-note`, two `This is a demo reply.` texts exist and the pill shows `Gemini 2.5 Pro`.
- **Proof.** Screenshots `picker-local-tab`, `picker-anyrouter-tab`, `picker-anyrouter-filtered-*`, `chose-claude`, `first-reply`, `second-reply-after-switch`. Journey: `model-picker`.

## Gotchas

- The demo engine does not echo which model answered. The pill value is the proof of the switch, not the reply text.
- The sheet opens at medium height; filter instead of scrolling to reach a row.
- The signed-out prompt needs `-ARDemoSignedOut YES`; no journey covers it yet.
