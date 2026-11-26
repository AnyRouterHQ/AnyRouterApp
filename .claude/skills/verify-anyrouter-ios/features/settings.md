# Settings

A sheet with a navigation stack: account card, grouped pages (Models, Chat, Appearance, About), a "Show keyboard on launch" toggle and a Delete conversation history action. Theme is chosen on its own page.

## Sub-features

- `settings-drill` opens pages (Inference, Privacy, Licenses, Manage models) and goes back.
- `settings-keyboard-toggle` "Show keyboard on launch" persists and focuses the composer at launch.
- `settings-theme` Light, Dark and System apply live while the sheet is open and persist after relaunch.
- `settings-account` account card for signed-in and signed-out states (screenshot only, see ScreenshotTests).
- `settings-response-details` Response Customization, "Show response details" toggle (`settings-show-response-details`): the line under each reply (`response-details`) shows by default, hides when off and stays hidden after a relaunch (journey `response-details`).
- `settings-delete-history` confirmation dialog (not automated).

## How to get to it (user POV)

- Open the sidebar and tap the gear button labeled `Settings`.

## Driving it with the journeys harness

Preconditions:

- Demo launch. Relaunches pass `-ARDemoKeepSettings YES`.

- **Drill down.** Tap a row (`Inference`, `Privacy`); the navigation bar title matches; tap the back button; `Settings` is shown again.
- **Toggle.** Reveal the switch `settings-show-keyboard`, tap it; its value becomes `1`. Terminate, relaunch with keep-settings: `app.keyboards` is non-empty at launch. Turn it off, relaunch: no keyboard.
- **Theme.** Settings, `Theme`, tap `Dark`. The screen mean brightness drops below 0.35 while the sheet is still open. Relaunch with keep-settings: still dark. Repeat with `Light` (above 0.6).
- **Proof.** Journeys `settings` (light and dark passes) and `theme` (single pass). Look at `page-*`, `keyboard-toggle-*`, `relaunch-*` and `picked-*` screenshots.

## Gotchas

- The theme journey assumes the CI simulator is in light system appearance; if it is not, its first assertion fails and says so.
- Do not pass `-ARAppearance` on a relaunch that tests persistence; it overrides the stored theme.
- `UITests/ThemeTests.swift` (in the screenshots target) also cycles themes with screenshots but asserts nothing about brightness.
- The Version row hides a diagnostics copy after 7 taps; it writes to the pasteboard and is not automated.
