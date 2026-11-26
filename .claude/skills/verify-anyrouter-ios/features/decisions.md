# Decisions

A sheet for running a yes/no decision flow: a model, a state text, optional questions and a Run button. The screen and its ids exist, but the current UI has no way to open it.

## Sub-features

- `decisions-form` Run is disabled until there is text and a question.

## How to get to it (user POV)

- Open the sidebar and choose `Decisions` (`sidebar-decisions`) under More.

## Driving it with the journeys harness

Preconditions:

- Demo launch. Not yet run through the journeys harness; `UITests/DecisionsTests.swift` covers the entry point.

- **Open.** Open the sidebar, tap `sidebar-decisions`. The Decisions sheet opens.

## Gotchas

- Do not report Decisions as verified through the screenshot of another screen.
- Once an entry point exists, add a journey and move the ids `decisions-model`, `decisions-state`, `decisions-add-question`, `decisions-run`, `decisions-question-prompt` into it.
