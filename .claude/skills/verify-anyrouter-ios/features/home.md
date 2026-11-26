# Home

The empty chat a user sees on a new chat: logo, greeting, a subtitle naming the active model, and a row of prompt-preset chips above the composer.

## Sub-features

- `home-greeting` shows "What can I help with?" and the logo; it is a button (`home.greeting`).
- `home-tip` tapping the greeting swaps the subtitle (`home.subtitle`) for a tip.
- `home-subtitle` names the active model, for example "Using Apple Intelligence · on device".
- `home-presets` shows preset chips; tapping one fills the composer, long-press offers "Send now"; the shuffle button reorders them.

## How to get to it (user POV)

- Launch the app.
- Choose `New chat` from the chat toolbar or the sidebar.

## Driving it with the journeys harness

Preconditions:

- Demo launch, no thread selected.

- **Greeting.** Wait for the element `home.greeting`. The composer shows the prompt `Ask anything`.
- **Tip.** Tap `home.greeting`; the label of `home.subtitle` changes.
- **Presets.** Tap the button labeled `Shuffle presets`; the chips change. Tapping a chip puts its prompt in the composer (`composer.input`).
- **Proof.** `step("home")` then `audit(app, "home")`, in all three passes. Journey: `composer` (first step).

## Gotchas

- The tip tap is hidden (not announced as a button, hint "Shows a tip"); the composer journey covers it.
- The chips are a horizontal scroll row; at large text they clip at the right edge by design. Judge from the screenshot.
- The shuffle order depends on the day seed, so assert the chips changed, not which ones appear.
