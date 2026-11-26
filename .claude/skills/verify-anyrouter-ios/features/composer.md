# Composer and keyboard

The input at the bottom of the chat: a round Add menu, a growing text field, and a trailing button that is Presets when empty, Send when there is text and Stop while a reply streams.

## Sub-features

- `composer-focus` tapping the field raises the keyboard.
- `composer-send` text enables `Send`; sending shows the user message and the reply.
- `composer-dismiss` tapping the message area dismisses the keyboard.
- `composer-keyboard-on-launch` the setting "Show keyboard on launch" focuses the field at launch (driven from the settings journey).

## How to get to it (user POV)

- Tap the text field (`composer.input`).
- Choose `Send`, or press Return on a hardware keyboard (Shift-Return adds a line).

## Driving it with the journeys harness

Preconditions:

- Demo launch on the home screen.

- **Focus.** Tap `composer.input`. `app.keyboards` becomes non-empty.
- **Type.** `typeText("Hello there")`. The button labeled `Send` exists and is enabled.
- **Send.** Tap `Send`. Static texts `Hello there` and `This is a demo reply.` appear.
- **Dismiss.** Tap the message area at normalized offset (0.5, 0.3). `app.keyboards.count` becomes 0.
- **Proof.** Screenshots `typed`, `sent-and-replied`, `keyboard-dismissed`. Journey: `composer`.

## Gotchas

- The text field is a vertical-axis TextField, so it can surface as a text view; use the `composer.input` id through `descendants(matching: .any)`.
- The demo engine answers instantly; streaming and the Stop button are not exercised.
- Tapping the lower part of the screen can hit the composer and refocus it. Tap above the middle.
