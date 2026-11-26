---
name: verify-local-model-lifecycle
description: Check a change to the local model lifecycle against its TLA+ model. Use when you touch the generation gate, the cache of loaded weights, warm-up, unload, delete of a local model, or the GGUF and MLX engines' stream(), or when the verify-formal CI job fails.
---

# Verify the local model lifecycle

The part of AnyRouter where an ordering bug costs the most and tests reach the least: chats, warm-ups, memory-warning
unloads and Hub deletes all race for one gate and one set of loaded weights, on a phone with room for one model.
A TLA+ model (checked with TLC) tries every order of those steps inside a stated bound. A script ties the model to
the Swift code. CI runs both on every push that touches the covered files, on a Linux runner.

## What is proven

Within the bound below, in every order of steps, these hold on the code as it is:

| Invariant | In plain words | Harm if it breaks |
|---|---|---|
| OneHolderPerGate, OneGenerationAtATime | One load, generation or warm-up holds the gate at a time, across both engines | Two contexts double the KV cache, the app is killed |
| GateMatchesHolders, NoGateLeak | The gate is busy exactly while someone holds it and is free when all requests are over | One failed stream blocks every later chat |
| AtMostOneModelInMemory | The weights of one local model are in memory at most, on either engine | The fit check judges a model as if it were alone; two models do not fit |
| LoadOwnedByHolder | Only a gate holder asks the cache for weights, so the cache never has two loads at once | Two models load at once |
| DeletedModelNotResident | When a delete is over, the cache does not hold the deleted model | Gigabytes held for a model the user deleted, its file kept alive by the mapping |
| CancelledInQueueNeverLoads | Stop on a stream that waits at the gate loads nothing | A model loads, and evicts the one in use, for a reply nobody reads |
| UnloadHonoredWhenIdle | After a memory warning or Unload and with no chat running, nothing is loaded unless a load started after it | The weights stay resident under memory pressure |
| EveryRequestEnds (liveness) | Every chat and warm-up ends, under fair scheduling | A chat waits at the gate for ever |

Bound (TLC, formal/LocalModelLifecycle.cfg): 3 chat streams, 1 warm-up, 3 models (2 GGUF, 1 MLX), the GGUF model g1 and
the MLX model m1 each deleted once, unloads at any time and any number of times, Stop on any stream. 706,926 distinct
states, under a minute on a CI runner. Liveness (formal/LocalModelLifecycleLive.cfg): 2 chats, 1 warm-up, g1 deleted once, 51,026 states.

## What is not covered

- A pass covers the model, not the Swift. The tie to the code is the conformance script: it checks that named lines
  exist in the named functions in the named order. A change that keeps the lines but changes what they do is invisible to it.
- More than 3 chats, 3 models or a second delete of the same model. Reinstall (the download replacing weights at the same path, the `installedAt` key) is not modelled.
- llama.cpp and MLX themselves: a load is one step that may succeed or fail, a generation is one step that ends.
- Memory sizes. "One model in memory" is counted in models, not bytes. The mapped file's pages and the KV cache are not modelled.
- `ResidentModels` calls from outside the gate: the join path of the cache (`loading.key == key`) is used only by the smoke report's `promptReport`. The model proves the gate keeps every other caller out of it (LoadOwnedByHolder).
- The main-thread freeze reports at launch and while loading. Loading runs off the main actor, nothing in the model sees the main thread. They stay covered by MainThreadWatchdog and the hang-guard tests.
- The download state machine (ModelDownloadState), the AnyRouter sign-in flow, MCP, Apple Foundation Models.

## What the check found

Until the commit "fix(local): one gate and one loaded model for both engines ..." the code had defects 1 to 4 below. Each old
design is a file under formal/mutants (six files), and CI shows its invariant failing on it, so a pass is not blind.

1. **Two gates, two caches** (two-gates, two-caches). A GGUF chat and an MLX chat could run together, and after a GGUF chat then an MLX chat both models stayed in memory. Fix: one `LocalResidency` (Engines/Local/LocalResidency.swift) shared by both engines.
2. **Memory warning lost during a load** (unload-keeps-load). `unload()` cleared the loaded model but not the load in progress, so the weights were cached when the load ended. Fix: `unload()` and `unload(ifID:)` also clear `loading`.
3. **Delete raced a send** (delete-unloads-first). `LocalModelHub.delete` unloaded, then removed files. A chat or warm-up that began between the two loaded the model again and kept it after its files were gone. Fix: files first, then unload.
4. **Stop did not stop the load** (no-cancel-check). A stream cancelled while it waited at the gate still read the manifest and loaded its model, evicting the one in use. Fix: `try Task.checkCancellation()` right after the gate.
5. **Gate leak** (gate-leak). Not a defect today: the gate is released after the do/catch on every path. The mutant releases only on success and one failed stream blocks the gate. It keeps that rule from regressing.

## Does your change touch the verified code?

Covered files and what each step of the model comes from (the CODE lines above each action in the spec are the exact list):

| File | Function | Model |
|---|---|---|
| Engines/Local/LocalResidency.swift | `GenerationGate` acquire, tryAcquire, release | StartChat, StartWarm, Release |
| Engines/Local/LocalResidency.swift | `ResidentModels` weights, unload, unload(ifID:) | CacheRequest, LoadSucceed, LoadFail, UnloadAll, UnloadIfEffect |
| Engines/Local/GGUF/GGUFEngine.swift | stream, warm, loadWeights, unload | GateExit, RunFinish, Cancel, StartWarm |
| Engines/Local/MLX/MLXEngine.swift | stream, unload | same, for the MLX engine |
| App/AppState.swift | engine setup, memory-warning observer, `warmUp`, hub unload closure | one shared residency, UnloadAll |
| Features/Services/LocalModelHub.swift | delete(modelID:) | DeleteStep1, DeleteStep2 |
| Features/Services/MemoryMonitor.swift | unload, appInBackground | UnloadAll |

Last confirmed that the model describes these files at commit: **5ee5c22**.
Check what changed since:

```sh
git diff --stat 5ee5c22..HEAD -- Engines/Local/LocalResidency.swift Engines/Local/GGUF/GGUFEngine.swift Engines/Local/MLX/MLXEngine.swift App/AppState.swift Features/Services/LocalModelHub.swift Features/Services/MemoryMonitor.swift
```

If that prints nothing, the model is still in step. If it prints a change, read it against the table, run the checks,
and only after you have confirmed that the spec describes the code at HEAD replace 5ee5c22 with HEAD's short SHA.
Do not move it for a change you did not read.

## Run the checks

CI runs them: `.github/workflows/verify-formal.yml` (job `conformance` and job `tlc`), on push and pull request
for the covered paths. On the maintainer's Mac there is no Java, so do not run TLC there; push and read the run
(`gh run watch`, `gh run view --log-failed`).

With Java 11 or newer (a contributor's machine or a Linux box):

```sh
python3 -I scripts/formal-conformance.py   # does the Swift still match the model? no Java, a second
scripts/formal-check.sh all                # main (invariants), live (every request ends), mutants (each old design must break)
```

`scripts/formal-check.sh` downloads TLC v1.7.4 once and checks its SHA-256.

## Read the result

Read every TLC result with the pstack `/statechart` skill. It shows each invariant violation as its shortest path in
plain words. When the check passes, it draws a chart of how the system moves between states. Use it with the spec
and cfg in formal/. TLC's own trace has the same steps, named by action, each with the line of the spec.

**Conformance fails.** The message names the spec line and the Swift line. Either the code moved on or the
spec is stale. Decide which is intended:
- The code change is intended: change the model to match (an action, a CODE line, a flag), run TLC, then fix the line.
- The code change is not intended: restore the line.
Never edit a CODE line only to make the script pass; say in the commit what the model change is.

**TLC says an invariant is violated.** Replay the trace against the real code before you believe it, one step per
action: an action name maps to the CODE lines above it in the spec. If the code can do those steps in that order,
it is a bug: report it with the trace in the code's words and fix the code (or, if you must ship first, add the
invariant to a known-findings list in your report, never weaken it). If the code cannot, the model is too loose:
find the step that the code keeps out (a guard, a lock, an actor hop) and put it in the model with its CODE line.
Do not delete the invariant and do not shrink the bound to make it pass.

**A mutant passes (its invariant no longer fails).** The invariant became blind or the model changed so that
the old design is no longer reachable. Fix the model: a check that cannot fail proves nothing.

## Change the design on purpose

1. Edit the spec first. A new caller of the gate, the cache or an unload: add the action, its CODE lines, and the file to the matching ONLY line.
2. A new design decision: add a FLAG constant, a WHEN line that says what it looks like in the code, set it in formal/LocalModelLifecycle.cfg, and add a formal/mutants file that turns it back and names the invariant that must fail (the script checks that every flag has one).
3. Run `scripts/formal-conformance.py` and `scripts/formal-check.sh all` (or push and read CI).
4. Update the table above and move 5ee5c22.

## How this skill was proven

On 2026-11-27 four scratch changes to the real code were each caught by `scripts/formal-conformance.py` and then
undone: removing `try Task.checkCancellation()` from GGUFEngine.stream, removing `loading = nil` from `ResidentModels.unload()`,
moving `await unloadModel(modelID)` before the file delete in LocalModelHub.delete, and giving MLXEngine its own
`GenerationGate()`. Each old design is also a mutant that TLC rejects (CI step "Each invariant fails on the old design").
