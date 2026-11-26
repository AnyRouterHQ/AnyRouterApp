# AnyRouter verification map

This directory is the maintained source for verifying the user-facing behavior of the AnyRouter iOS app. Read the index, then use the matching feature file as the recipe.

## Baseline preconditions

- Verification runs on GitHub Actions through `.github/workflows/verify-ui.yml`. Nothing runs on the maintainer's Mac.
- Every journey launches with `-ARDemoData YES`: five sample threads (one pinned, one with a markdown answer and a code block), Apple Intelligence available, two installed GGUF models (Qwen3 0.6B, Llama 3.2 1B Instruct), one download at 42% (Gemma 3 1B), two not installed, AnyRouter signed in with six cloud models, no network.
- Demo engines reply `This is a demo reply.` to any message.
- Settings are wiped on each launch unless `-ARDemoKeepSettings YES` is passed, so a relaunch test passes it on the second launch.
- Simulator: iPhone 17 Pro class (iPad Pro 13-inch optional), light system appearance, software keyboard.

## Driving conventions

- Start every recipe from the baseline state unless its preconditions say otherwise.
- Prefer accessibility ids and labels over coordinates. Navigation bar titles are stable handles.
- Passes: light, dark, large text (Dynamic Type AccessibilityXL). A recipe says when it runs once.
- iPhone: the sidebar is a drawer behind the `Menu` button. iPad: it is a split-view column.
- Journey ids for the workflow: `theme`, `drawer`, `composer`, `model-picker`, `settings`, `hub`.

## Proof and skip reporting

- Capture the user action and the resulting state with `step(...)`, and run `audit(...)` on each new screen.
- Toggle proof is the persisted effect after a relaunch.
- Record the feature ID and the pass with every claim. Report an unreachable path with the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the journeys harness`, `Gotchas`.

## Features

| Feature | Journey id | Status |
|---|---|---|
| [Home](./home.md) | composer (home step) | greeting and presets covered by the composer journey; the tip tap does not exist in the code |
| [Composer and keyboard](./composer.md) | `composer` | automated, passing (run 45814540560) |
| [Sidebar](./sidebar.md) | `drawer` | automated, passing (run 45857039234) |
| [Model picker](./model-picker.md) | `model-picker` | automated, passing (run 45814540560) |
| [Settings](./settings.md) | `settings`, `theme` | automated, both passing (runs 45862667608, 45814540560) |
| [Hub (Manage models)](./hub.md) | `hub` | written; last run (45865789108) stopped at closing the filter menu, fix pushed and not yet re-run |
| [Decisions](./decisions.md) | none | no entry point in the current UI; `UITests/DecisionsTests.swift` is stale |
| [Integrations](./integrations.md) | none | not automated: needs a mocked MCP server in demo data |
| [Attachments](./attachments.md) | none | not built: the Add menu items are disabled under "Coming soon" |

## Differences from the operator brief

- The hub is a single list with Sort and Filter menus; Hugging Face repo search opens a second sheet only after a search query and needs the network, so it is not driven.
- There is no hidden tip tap on home. The only hidden tap is the Version row in Settings (seven taps copy diagnostics, see `SettingsLogic.diagnosticsTapCount`).
- Theme is a Settings page (Settings, Theme, Light/Dark/System), not a toggle.
