# Agent design: memory, context and resumable runs

The design of the app agent as built. PLAN.md D28 is the decision and lists what is still open. The section numbers are cited from code comments, so keep them.

The agent runs on three engine classes: Apple Foundation Models (about 4k tokens), local GGUF and MLX models (4k to 8k, slow), and AnyRouter cloud models (128k and more). Labels: **Verified** means read in a primary source (see Sources). **Inferred** means a reading of the evidence, to measure before relying on it.

## Principles

Device engines have no memory tools: the app recalls before the send and saves after the reply, as `WebGrounding` does for search, because extra tools would push the clock, calculator, search and page reader out of the 4-tool window (Apple advises 3 to 5, Verified). Cloud models get `memory` and `search_chats`. One `PromptAssembler` builds every request, stable part first. One app loop (`AgentLoop`) serves cloud and local engines, and Apple keeps its framework loop because the framework runs the tools. Skills, notes and subagents are cloud only. Escalation to a cloud model is a button, never automatic.

## 1. Runs

### 1.1 State

One reply is one run. `AgentRunRecord` (SwiftData) holds the thread, the reply's message id, the model, a status (`running`, `awaitingApproval`, `finished`, `failed`, `cancelled`, `interrupted`), the next node, the round count and `AgentRunState` as JSON. That state holds each tool round (the text and every call the model asked for) and the side-effect class of each call the user was asked about. Text, steps and reasoning stay on the reply's `MessageRecord`. A run that ends is deleted: only an unfinished run has anything to resume. Unknown raw values read as `interrupted` or `finish`, so a build never resumes a run it cannot place. Notes live on the thread (`ThreadRecord.notesData`), not the run.

### 1.2 Step graph

`AgentGraph` is a pure transition function over `AgentNode`, so tests drive it without a model.

Nodes: assemble, compact (at most once per run, on overBudget; a failed compact sends as is with a note), generate, act, approve (the run is saved as `awaitingApproval`; a denial becomes the denied-text result), finish, then remember (after the reply shows, never blocks it). After `act`, results go back to assemble so they are clipped to what is left. `roundLimit` runs one last generate with tools off. Any failure or stop goes to finish.

There is no plan node. A plan is an extra model call before every answer, which costs seconds to minutes on a local model for a gain nobody measured on small models. Cloud runs plan through the notes tool (section 4). Interrupts follow LangGraph's rule (Verified): code before an interrupt runs again on resume, so it must be idempotent. The interrupt sits before the call runs.

### 1.3 Checkpoints and resume

The run is saved when it starts, when a round ends, when a call gets its result, when it stops for approval, and when it ends. Never per token. `startStream` marks the new reply `interrupted` and `finish()` clears the mark, so a kill leaves the marker and no launch heuristic is needed. A launch sweep (`AgentRunSweep`) reads every unfinished run.

- `running`: partial text and "The reply stopped when the app closed." with Retry. A cloud request is never silently restarted, because it costs money.
- `awaitingApproval`, cloud or local: the approval card is back on its step, and Allow or Deny continues from `act`, rebuilt from the saved rounds.
- `awaitingApproval`, Apple: the card is back. On Allow the tool runs and a new Apple turn starts with the earlier text and the result as text. The framework loop cannot be re-entered, and building transcript tool entries by hand is not documented (Verified).

Per tool step: a step with a result never runs again. A step waiting for approval asks again. An approved read with no result runs again. An approved write or external call with no result does not run again: the row says "This may not have finished. Check, then try again." and the model is not told it ran.

### 1.4 Engines

One call per engine: run one round and report what the model asked for, without running it. AnyRouter wraps `streamRound`. GGUF and MLX run one `base.stream` plus `LocalToolParser`. Apple keeps `AppleFoundationEngine.stream(tools:)` and gets a `ToolHost` that saves the run around each `execute`, so it has the same rows, checkpoints and resume rule. The host still owns approval and execution, so confirmation stays in one hook (WWDC26 347). `ToolRunScope` handles cancellation.

## 2. Memory

### 2.1 What is remembered

`MemoryRecord` is a short statement (at most 280 characters, a chat summary at most 600) with a kind, an origin, a scope, its source chat and message, and use counts. Kinds: **profile** (who the user is), **preference** (how to answer), **fact** (stated, not about answering), **note** (pinned by hand), **chatSummary** (one per chat, for `search_chats`). Profile, preference and note items make the always-on profile. Facts and chat summaries are recalled when they match.

### 2.2 Where it lives

SwiftData on the device, in the chats' store. Nothing syncs. Recall is lexical, as Hermes does with plain FTS5 and no model call (Verified). On-device embeddings (`NLContextualEmbedding`, unit M7) are only for strong meaning-only hits, and dimension and languages are read at run time because the docs give no numbers (Verified).

### 2.3 Writes

- Typed in Settings, "Remember this" on a message: all engines, no model call.
- "Remember that ..." in the user's message: all engines, no model call. A pure classifier in English and Vietnamese ("remember that", "from now on", "nhớ rằng", "từ giờ") saves the sentence without the cue.
- Extraction after the reply: Apple only, one guided-generation call, at most 3 candidates, only for a first-person statement. Off on GGUF and MLX: a second generation blocks the one loaded model.
- `memory` tool: cloud, in the run.
- Chat summary: one short call by the D30 rule (Apple when ready, else the chat's own model, never a cloud model for a device chat), when a chat of 6 or more messages loses focus and has no compaction summary. GGUF and MLX reuse the compaction summary.

Every write shows one "Memory updated" `TraceRow` with Undo and Edit. A write past a cap or a duplicate says so in the same row. Caps follow Hermes: refuse past the cap, never compact silently (Verified). The caps are 60 profile, preference and note items and 500 facts. Nothing is removed without the user.

### 2.4 Recall

**Profile.** Pinned notes, then preferences, then profile items, newest first within a kind. Items are added whole until the engine's profile budget is spent, never cut. The list is frozen at a chat's first send in `ThreadRecord.profileSnapshot`, as Hermes freezes its snapshot to keep the prompt cache (Verified). Edits apply from the next chat.

**Device engines, before the send.** Score facts and chat summaries against the last message with BM25 over folded, diacritic-insensitive words. An exact match scores above a match found only after folding, because folding merges Vietnamese words that differ by a tone mark. Keep the top 3 above a floor within the hit budget, put them before the last user message as "Things the user told you before:", and show "Used N memories" in the footer with Forget on each. Apple's TN3193 says to run a lookup yourself when the data is always needed (Verified).

**Cloud.** The same pre-send hits, plus two tools, as Anthropic advises loading content just in time (Verified). `memory` has one `action`: `search`, `add`, `patch`, `remove`. One tool costs one schema. `search_chats` takes a query and returns at most 5 results (title, date, summary, one matching message cut to 300 characters). It scans the store lexically, over at most 200 candidate messages.

### 2.5 Controls

Settings › Memory: **Use memory**, **Save memories automatically**, **Use memories from on-device chats in cloud chats** (off by default), a list by kind with each item's source chat, and **Delete all memories**. A chat's More menu has **Don't use memory in this chat** (`ThreadRecord.memoryOff`).

### 2.6 Privacy

A device chat's reply came from Apple, GGUF or MLX. A cloud chat's came from AnyRouter. A memory is `deviceOnly` when it came from a device chat, `everywhere` when it came from a cloud chat or was typed in Settings.

- Profile and recalled items: a device chat gets all. A cloud chat gets `everywhere` items, and `deviceOnly` ones only with the cross switch on.
- `search_chats`: no tool on device (pre-send recall reads all chats). On cloud it covers cloud chats only, unless the cross switch is on.
- Extraction and summaries: the device on a device chat, the chat's own model on a cloud chat.
- The first `deviceOnly` item sent to a cloud model shows one notice in the chat.

Eval E8 asserts the cloud rule on the request body.

## 3. Context per engine

### 3.1 Count tokens honestly

Apple uses `SystemLanguageModel.tokenCount(for:)` (iOS 26.4 and later) and `contextSize`. GGUF and MLX use the model's tokenizer. Cloud and every fallback use `TokenCountLogic.estimate`: a word with any non-ASCII letter counts one token per character and everything else a third, because Apple gives about one token per character for Chinese, Japanese, Korean and Vietnamese (Verified). It overcounts English a little, the safe side for a 4k window.

### 3.2 The prompt assembler

The stable prefix pays on cloud now, where the upstream caches prefixes (Manus: cached input at a tenth of the price, Verified). It pays on GGUF after F3 keeps the KV between turns, on MLX after S7, and on Apple only if one session per open chat replaces the per-reply session.

`PromptAssembler` is one pure function from input and budget to `AssembledPrompt`, with the tokens used per section for the context meter. Sections, in send order: (1) app and custom instructions and tool guidance, (2) the frozen profile, (3) the skills index (cloud), (4) tool specs in one fixed order, (5) the compaction summary, (6) recent turns, append only, (7) memory hits, web grounding and @ mentions, (8) notes, (9) this run's calls and results.

- Sections 1 to 4 are the stable prefix. No time, date or counter in them: the date comes from the clock tool, because a timestamp at the start is the classic cache breaker (Manus, Verified).
- Turns are never edited. Compaction moves only section 5 and the start of 6, and the summary stays out of the system message.
- No section adds a message. Sections 5 and 7 merge into a user message's text, so roles alternate. Gemma-style templates reject two user messages in a row.
- Apple stays one string: sections 1 to 4 go to `instructions`, 5 to 9 to the prompt.

### 3.3 Budgets

Tokens. Each is checked with the counter in 3.1.

| Section | Apple 4,096 | Local 4,096 | Local 8,192 | Cloud |
|---|---|---|---|---|
| Output reserve | 700 | 700 | 1,024 | the model's `max_tokens` |
| Profile | 120 | 120 | 200 | 500 |
| Skills index | 0 | 0 | 0 | 1,500 |
| One matched skill's steps | 250 | 250 | 400 | 0 |
| Memory hits | 150 | 150 | 300 | 1,500 |
| One tool result | min(400, a third of what is left) | same | min(800, a third of what is left) | 20,000 characters |
| Compaction trigger | 80% of window minus reserve | same | same | min(80% of window, 64,000) |

The cloud trigger at 64,000 is a choice, not a measurement: input is most of an agent's cost (Manus: about 100 input tokens per output token, Verified). Measure cost per reply when changing it.

### 3.4 Clearing tool results inside a run

Nothing is replayed across turns. Inside a run:

- Each result is clipped to the per-result limit from what is left in the window.
- When the next round would not fit, results older than the newest 3 become one line, such as "[Result cleared: fetch_url https://example.com/page, 4,210 characters]". The URL stays so the model can fetch again (Anthropic's context editing keeps 3 and Manus's restorable compression, Verified).
- On cloud, clear only when it frees at least 8,000 tokens, because each clear breaks the provider's prompt cache from that point (`clear_at_least`, Verified).
- Errors stay and are cleared last: Manus found failed actions in context stop the model repeating them (Verified).
- A call is never split from its result. The cloud API rejects a tool message without its call.

A **tool digest**, one line per call ("Searched the web for 'Da Lat weather'."), is appended to every assistant message that used tools, on every request. It is derived from the stored steps the same way each time, so the prefix stays append only, and it lets "read the second page again" work without replaying results.

### 3.5 Compaction

The trigger uses the assembler's count and the 3.3 budget. The cloud summary uses fixed headings: Goal, Constraints and preferences, Progress, Key decisions, Next steps, Critical context (pi, Verified). Apple and local keep a plain prompt, since headings cost tokens a 4k window lacks. The profile, memory hits, notes, the newest 4 exchanges and the tool digests survive without being summarized. On Apple, `contextSizeExceeded` maps to `ReplyFailure.Kind.contextTooLong`, compacts once and retries once. A second failure shows **Shorten chat**.

## 4. Techniques

**Todo recitation.** Cloud runs of 3 or more rounds get a `notes` tool that replaces a list of at most 10 items, recited after the last tool result (unit G5). Manus recites todos over about 50 calls per task, and pi says todo lists confuse small models (both Verified). Device runs are 4 rounds at most, too short to drift.

Not taken: masking tools by logit (the cloud API has none, and D14 rules out building llama.cpp's `common/` for it; the tool list simply does not change inside a run); a session tree and fork (Regenerate covers the common case); a background session review on device (battery and the loaded model); a local subagent (`LocalResidency` allows one loaded model, so it would queue behind its parent, and a cloud subagent from a device chat would send device text to the cloud).

### X1 Escalation

A device reply that failed with `contextTooLong` or `localOutOfMemory`, or any device reply through its menu, offers **Ask a cloud model** (`EscalationLogic`). The first time per chat a notice says the chat's text goes to AnyRouter. The chat continues with a "Switched to" note and counts as a cloud chat for 2.6 from then on.

### 4.2 Skills

A skill is written steps for one kind of task. Cloud models get an index (at most 1,500 tokens) and a `read_skill` tool. Apple and local get no index: before the send the app picks at most one enabled skill whose name and description share two content words with the question, and puts its steps in this turn's context if they fit the 3.3 budget, labeled as guidance that allows no tool. After a cloud run with 3 or more tool calls that ended well, the model may call `propose_skill`. The user sees the full text on an approval card, which is the only path to save, because later runs obey a skill. Imported SKILL.md files are untrusted data. Hermes asks skills to keep "lessons, not logs" (Verified).

## 5. Evals

### 5.1 Scripted suite (CI)

`RecordingEngine` keeps every request. Cloud tests read the `URLRequest` body through the stubbed session. Each scenario passes when:

- **E1** Recall across chats: a new chat's request holds "I'm vegetarian" from chat A before the last user message, and its footer lists one memory.
- **E2** Sections 1 to 4 and every earlier turn are byte-identical across turns and a relaunch.
- **E3** 200 mixed English and Vietnamese turns on the Apple budget: every request fits, the profile is in each, one summary exists.
- **E4** Four rounds of 6,000-character results at 8,192 tokens: each request fits, results older than 3 are stubs with their URL.
- **E5** A failing call is retried with other arguments, and a repeated identical call stops the loop.
- **E6** After a reopened store, Allow runs the waiting tool exactly once and round 2's request holds the result.
- **E7** A run killed while generating shows "interrupted" with Retry.
- **E8** A `deviceOnly` memory never reaches a cloud request body with the cross switch off.
- **E9** An approved write with no result at relaunch does not run again.
- **E10** Forget and Delete all remove the item from the store and the next request.

### 5.2 Live suite

LA11's tool-calling set runs in `model-smoke.yml` for GGUF and on device for Apple and MLX. The memory set is 10 prompts over 30 fixed memories: 5 to recall, 3 traps that share a word with a memory, 2 explicit saves. A judge model scores "used the right memory" and "invented a memory" over two runs.

### 5.3 Metrics

Recall at 3 of 0.9 or better (else lean on embeddings). Wrong recalls under 1 in 10 prompts. No scripted budget overflow. 95% or more of turns keep sections 1 to 3 byte-identical. Assemble plus recall p95 under 30 ms with 5,000 stored messages on a real iPhone. Follow PLAN's Measuring rule.

## 6. Open questions

1. Does AnyRouter serve an embedding model the app may call with the sign-in key? Until it does, embeddings stay on device.
2. How much of PLAN Q8 (what a reply stores: rounds, approvals, sections with token counts, finish reason) should the loop record?
3. Live evals (L1) still need a first run before any engine gets tools on by default.

## Sources

Apple: [managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window), [contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize), [Transcript](https://developer.apple.com/documentation/foundationmodels/transcript), [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding).
pi: [post](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/), [compaction](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/compaction.md), [skills](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md).
Hermes: [memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory), [skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills), [compression and caching](https://hermes-agent.nousresearch.com/docs/developer-guide/context-compression-and-caching).
LangGraph: [persistence](https://docs.langchain.com/oss/python/langgraph/persistence), [interrupts](https://docs.langchain.com/oss/python/langgraph/interrupts).
Anthropic: [context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool), [context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing).
Manus: [context engineering lessons](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus).
