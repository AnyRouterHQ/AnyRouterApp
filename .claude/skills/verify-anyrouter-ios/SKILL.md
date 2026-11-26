---
name: verify-anyrouter-ios
description: Verify the AnyRouter iPhone and iPad app (SwiftUI) the way a user uses it, by driving XCUITest journeys on a GitHub Actions iOS Simulator and reading the screenshots. Use to validate UI, UX, toggles, interactions and layout of a change, since this repo has no local Xcode or Simulator.
---

# Verify AnyRouter on iOS

The app is native SwiftUI. Nothing runs on the maintainer's Mac (no Xcode, no Simulator, laptop memory rule), so the "running app" is a GitHub Actions macOS runner. A journey is an XCUITest in `UITests/Journeys/` that taps, types and swipes through a real user path on demo data, attaches a screenshot at every step, and asserts the end state. You then download the evidence and look at it.

Read `features/README.md` first, then the feature file for what you are verifying.

## Launch

```bash
gh workflow run verify-ui.yml --ref main -f journeys=<ids|all|none> [-f flows=<UITests classes|all|none>] [-f ipad=true]
RUN=$(gh run list --workflow verify-ui.yml --branch main --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --interval 120 --exit-status
```

- `flows` runs the functional UI tests in `UITests/*Tests.swift` (for example `-f flows=KeyboardTests,ThemeTests`, or `all`; ScreenshotTests and PerformanceTests are excluded, they have their own workflows). The same run builds once for both. Nightly (03:17 UTC) it runs journeys and flows on iPhone, iPad Pro 13-inch and iPad mini; with `-f ipad=true` the iPad legs also run `PadLayoutTests`. Per-test pass/fail is in `evidence/results-<device>.txt`.
- Journey ids: `theme`, `drawer`, `composer`, `model-picker`, `settings`, `hub`, `response-details`. `all` runs every journey.
- The run builds once (about 8 minutes cold, less with the cache), boots an iPhone 17 Pro class simulator (plus iPad Pro 13-inch with `ipad=true`), and runs each journey in passes: light, dark, and large Dynamic Type (AccessibilityXL). The theme journey runs once because it changes the theme itself.
- The workflow only runs code that is pushed. Runner budget (AGENTS.md): dispatch on main only, one run at a time, and only when main CI is idle; ask the manager before a heavy run. A local edit is not verified until CI has run it.
- Never poll in a loop. The GitHub API rate limit is shared by every agent on this machine. One `gh run watch --interval 120` or one `gh run view` per two minutes.
- Ready means the run finished and the `verify-evidence` artifact exists. A green run with no artifact is a failure.

## Doctor

Read-only. Run before launching, and whenever a run looks wrong.

```bash
gh workflow list | grep -i "Verify UI"                       # workflow is on the default branch
gh run list --workflow CI --branch main --limit 1            # last main CI is green
gh api repos/AnyRouterHQ/AnyRouterApp/actions/artifacts --jq '.artifacts[] | select(.name=="verify-evidence") | {id, expired, created_at}' | head -3
```

- `gh workflow run` only finds a workflow that exists on the default branch (or the `--ref` branch it was pushed to).
- If main CI is red, a journey failure may be a build failure, not a UI one. Read the failing step first.
- Artifact retention is 14 days (`retention-days` in the workflow). Download evidence you need to keep.

## Drive

The journeys are the harness. Add or change one in `UITests/Journeys/`, extending `JourneyCase` (`JourneySupport.swift`):

- `runPasses { app, pass in ... }` launches once per pass. `launch(_:keepSettings:)` launches on demo data.
- `step("name")` attaches a screenshot and writes `<journey>/<pass>-<NN>-<name>.png`. Call it after each action and again for the resulting state.
- `audit(app, "screen")` runs `performAccessibilityAudit` and records findings. Findings are evidence, not test failures.
- `openSidebar`, `openSettings`, `reveal(_:in:)`, `composer(_:)`, `brightness()` cover the common moves.
- The iPhone drawer stays in the accessibility tree while closed, so `exists` is not "visible". Test `isHittable` (see `waitHittable`).
- Prefer accessibility ids and labels. Existing ids: `composer.input`, `settings-show-keyboard`, `decisions-*`, `memory-menu`. Labels: `Menu`, `New chat`, `Model` (its value is the selected model name), `Send`, `Stop`, `Add`, `Presets`, `Settings`. When a handle is missing, add `.accessibilityIdentifier` in the app in the same commit as the journey.
- Demo launch arguments (see `App/DemoData.swift`): `-ARDemoData YES` (required: in-memory threads, fake engines, fake hub and account, no network), `-ARDemoSignedOut YES`, `-ARDemoOnboarding YES`, `-ARAppearance light|dark`, `-ARDemoKeepSettings YES` (keep settings from the previous launch, used to prove persistence across a relaunch).
- Add the new class to the `case` list in `.github/workflows/verify-ui.yml` and to `features/`.

## Evidence

```bash
gh run download "$RUN" -n verify-evidence -D <scratch>/verify/$RUN
```

Layout: `<scratch>/verify/<run-id>/<device>/<journey>/<pass>-<NN>-<step>.png`, where `<journey>` is the test class name without `Journey`, lowercased (`modelpicker` for model-picker). Also `<device>/results.tsv`, `<device>/audit.tsv`, `summary-<device>.json` (xcresult test summary) and `journeys.md`.

Then Read the PNGs and judge them. Read `journeys.md` first for the failed tests, then open the screenshots of the failing step and the step before it.

Proof standards:

- Drive the real path: taps, typing, swipes, relaunch. No internal setters, no test-only buttons.
- Capture the action and the resulting state, not only the final screen.
- A toggle is proven by its persisted effect after a relaunch, not by the switch flipping.
- Assert the end state in code and attach the screenshots. A passing test with unread screenshots is half a proof: look for clipped text, overlap, wrong colors, an unexpected keyboard, an empty screen.
- The network is faked by demo data. AnyRouter cloud calls, OAuth and real model downloads are not exercised here. Say so when a change touches them.
- A journey that fails because demo data lacks a precondition reports the failure. Do not weaken the journey.
- State in the report which passes (light, dark, large text) and which device you looked at.

## Cleanup

Nothing runs on this Mac, so there is nothing to tear down except local scratch.

- Remove only `<scratch>/verify/<run-id>` folders you created and no longer need. Never remove the evidence you cite in a report.
- Do not cancel runs you did not start. `gh run cancel <id>` only for your own run.
- The CI artifact expires by itself after 14 days.

## Helpers

- `scripts/journeys-report.py <evidence-dir>`: builds `journeys.md` (table of journeys, passes, steps, audit findings, failures, screenshot list). The workflow runs it; run it again on a downloaded folder with `python3 .claude/skills/verify-anyrouter-ios/scripts/journeys-report.py <scratch>/verify/<run-id>`.

- `scripts/ux-score.py` (repo root): scores the screenshots and the evidence against `docs/ux-rubric.md`. `ux-score.yml` runs it after every Screenshots and Verify UI run on main; read the job summary or download the `ux-score-screenshots` and `ux-score-verify-ui` artifacts. `audited.tsv` (one row per `audit()` call) is what lets it tell a clean audit from no audit, so keep `audit()` calling it.

## Findings the harness already surfaced

- The large-text pass shows model names truncated to "AnyRo…" and "Claude Sonn…" in the picker rows at AccessibilityXL.
- The composer, home greeting and chips use fixed font sizes and do not scale with Dynamic Type.
- `performAccessibilityAudit` reports contrast failures, clipped text, unsupported Dynamic Type fonts and small hit areas; see `<device>/audit.tsv`.

## Keeping it honest

Run `/pstack:maintain-verification-skill` when features change. `features/README.md` lists which features have a journey and which do not yet.
