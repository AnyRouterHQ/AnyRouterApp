# Decisions

A sheet for running a yes/no decision flow: a model, a state text, optional questions and a Run button. The screen and its ids exist, but the current UI has no way to open it.

## Sub-features

- `decisions-form` Run is disabled until there is text and a question.

## How to get to it (user POV)

- No entry point today: `ShellModel` can present it for the `.decisions` route, but nothing sets that route, and the sidebar has no Decisions row.

## Driving it with the journeys harness

Preconditions:

- None can be met through the UI.

- **Status.** Report this feature as unreachable. The attempted path is the sidebar and Settings; neither lists Decisions.
- **Stale test.** `UITests/DecisionsTests.swift` taps `sidebar-decisions`, which no longer exists, so it fails in the screenshots workflow. Fix or remove it when the entry point is decided.

## Gotchas

- Do not report Decisions as verified through the screenshot of another screen.
- Once an entry point exists, add a journey and move the ids `decisions-model`, `decisions-state`, `decisions-add-question`, `decisions-run`, `decisions-question-prompt` into it.
