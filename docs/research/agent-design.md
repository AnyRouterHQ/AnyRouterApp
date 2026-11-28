# Agent design: memory, context and resumable runs

Date: 2026-11-28. Design only. Nothing here was built or run. Lane B implements from it.

Goal: the agent in the AnyRouter iOS app remembers what the user told it across chats, keeps track of a long chat, and works well on every engine the app has. Those engines are Apple Foundation Models on the device (about 4k tokens), local GGUF and MLX models (4k to 8k tokens, slow), and AnyRouter cloud models (128k tokens and more).

Labels follow `docs/research/local-agent.md`. **Verified** means read in a primary source on 2026-11-27 or 2026-11-28, with the URL in Sources. **Known** means stable behavior that was not re-read for this document. **Inferred** means my reading of the evidence. **Code** means read in `AnyRouterApp` at `1b61f52`.

## Summary

- Memory comes first because the user sees it. One SwiftData table of short items, a **Settings › Memory** page, a small profile in every prompt, and a "Memory updated" row in the chat.
- On Apple and local models, memory is not a tool. The app recalls before the send and saves after the reply, as `WebGrounding` already does for search. Four memory tools would push the clock, calculator, search and page reader out of the 4-tool window.
- Cloud models get one `memory` tool and a `search_chats` tool.
- One prompt assembler builds every request from ordered sections with a token budget per engine. The stable part goes first, and the parts that change go last.
- Token counts must stop using "4 bytes is a token". Apple says Vietnamese runs about one character per token.
- A run becomes a small state machine saved at step boundaries. A killed app shows the reply as interrupted, with Retry. A pending approval comes back after a relaunch.
- Cloud and local tool loops move out of the engines into one app loop, because resume needs the loop state outside the engine. Apple keeps its own loop because the framework runs the tools.
- Skills, notes and sub-agents are for cloud models only. Escalation from a device model to a cloud model is a button, never automatic.

## 0. What the code does today

These facts bound the design. Each one changes a section below.

1. **Tool results and reasoning are never sent back on later turns.** `MessageRecord.toolTraceData` and `reasoningData` are display only (`Core/Records.swift`, decision T3). Clearing old tool results across turns already happens. The open problem is inside one reply, and what should carry over to the next turn. (Code)
2. **The local loop overflows inside one reply.** `LocalToolEngine.run` appends the raw round text and every result to the transcript for up to 4 rounds. `ToolProfile.compact` and `.apple` clip each result at 6,000 characters. Four rounds of that do not fit 8,192 tokens. (Code)
3. **The token estimate undercounts.** `CompactionLogic.tokens` is UTF-8 bytes divided by 4. Apple says a token is 3 to 4 characters in English and about one character in Chinese, Japanese, Korean and Vietnamese. A Vietnamese character with a diacritic is 2 to 3 bytes in UTF-8, so the estimate is low by a factor of about 2 to 3 for Vietnamese. (Code, Verified for the Apple ratio, Inferred for the factor)
4. **Apple runs its own loop.** `ApplePrompt.build` flattens the chat into one prompt, and every reply makes a new `LanguageModelSession`. The framework calls `AppleDynamicTool.call`, and approval is an in-process `await`. So Apple has no KV reuse across turns today, and no state the app can resume in the middle of a turn. (Code)
5. **KV reuse is not wired.** GGUF builds a new context per answer (F3 is open). `CompactionLogic.systemPrompt` appends the summary to the system prompt, so every compaction changes the first message. (Code)
6. **A killed app leaves a reply with no failure.** `startStream` inserts the assistant `MessageRecord` at the start and calls `save` only in `finish()`. If SwiftData autosave wrote the record before the kill, it comes back after a relaunch with partial text, no `metadata` and no `failure`. (Code for the save path, Inferred for autosave timing)
7. **The 4-tool cap is real.** `ToolProfile.apple` and `.compact` keep 4 tools. `ToolProfile.shaped` ranks unknown tool names last, so any new tool is dropped first on device. Apple's guidance is 3 to 5 tools. (Code, Verified)
8. **Out-of-scope note.** PLAN.md ` Out of scope for v1 lists agents and skills. Skills in this document are therefore marked as needing the operator's go-ahead.

## 1. Data shapes

### 1.1 The run and its state

One reply is one **run**. A run has a saved record and an in-memory state.

```swift
/// Core/AgentRun.swift (new, lane A reviews). Additive to ModelContainer.anyRouter.
@Model final class AgentRunRecord {
    @Attribute(.unique) var id: UUID
    var threadID: UUID
    /// The assistant MessageRecord this run writes into. Text, steps and reasoning stay there; they are not copied here.
    var messageID: UUID
    var modelID: String
    var statusRaw: String        // AgentRunStatus
    var nodeRaw: String          // AgentNode, the node to run next
    var round: Int
    /// AgentState as JSON, without anything MessageRecord already holds.
    var stateData: Data
    var startedAt: Date
    var updatedAt: Date
}

enum AgentRunStatus: String, Codable { case running, awaitingApproval, finished, failed, cancelled, interrupted }

/// Pure value. The loop reads and writes it; the record stores it.
struct AgentState: Codable, Equatable {
    var budget: ContextBudget
    /// Assistant text of each finished round, needed to rebuild the cloud and local transcripts on resume.
    var roundTexts: [String]
    /// Ids of the ToolSteps on the message that belong to each round. The steps themselves live on MessageRecord.toolSteps.
    var roundCallIDs: [[String]]
    /// Memory items put in this run's prompt, so the reply can show "Used 2 memories" and evals can check recall.
    var memoryHits: [MemoryHit]
    /// The call waiting for the user, if any.
    var pendingApproval: ToolCall?
    /// Set when the run stops for a reason the reply shows.
    var failure: ReplyFailure?
}

struct ContextBudget: Codable, Equatable {
    var window: Int              // tokens the engine accepts
    var outputReserve: Int       // tokens kept free for the answer
    var used: [PromptSection: Int]   // filled by the assembler, read by the context meter
}

struct MemoryHit: Codable, Equatable { var memoryID: UUID; var score: Double; var tokens: Int }
```

Why this shape:

- Text, reasoning and steps already live on `MessageRecord`. The run stores ids and round boundaries, not copies. A cloud run can carry 8 rounds of 20,000-character results (`MCPToolHost.maxResultCharacters`), and two copies of that in SwiftData would double the write on every step.
- `ToolStep` gets one optional field, `approval: ToolDecision?`, decoded with `decodeIfPresent` so stored replies still read. With it a step is in one of four states: waiting for approval, approved but not run, run with a result, or denied. Resume needs that distinction (section 1.3).
- Notes for long cloud runs live on the thread, not the run, so they carry over to the next turn: `ThreadRecord.notesData: Data?`, like `compactionData`.

### 1.2 The step graph

The nodes and edges are an enum and a pure transition function, so tests drive them without a model.

```swift
enum AgentNode: String, Codable {
    case assemble     // build the prompt from sections and budgets
    case compact      // fold old turns into the summary (existing CompactionLogic)
    case generate     // one model round: text, reasoning, proposed tool calls
    case act          // run the proposed calls through ToolHost
    case approve      // interrupt: wait for Allow or Deny
    case finish       // write metadata, failure or nothing; mark the run finished
    case remember     // after the reply: save memories the user stated (device) or the tool wrote (cloud)
}

enum AgentEvent { case fits, overBudget, compacted, compactFailed, calls([ToolCall]), noCalls,
                  needsApproval(ToolCall), decided(ToolDecision), resultsIn, roundLimit, failed(ReplyFailure), stopped }

enum AgentGraph {
    static func next(_ node: AgentNode, on event: AgentEvent, round: Int, maxRounds: Int) -> AgentNode
}
```

| From | Event | To | Note |
|---|---|---|---|
| start | | assemble | |
| assemble | fits | generate | |
| assemble | overBudget | compact | at most once per run |
| compact | compacted | assemble | |
| compact | compactFailed | generate | today's behavior: send as is with the note "Could not shorten the conversation" |
| generate | noCalls | finish | |
| generate | calls | act | |
| generate | roundLimit | generate | last round with tools off (`tool_choice: none` on cloud, no tool format on local), as today |
| act | needsApproval | approve | the run is saved with status `awaitingApproval` |
| approve | decided | act | a denial becomes `ToolResult.deniedText`, as today |
| act | resultsIn | assemble | the next round is budgeted again, so results are clipped to what is left |
| finish | | remember | runs after the reply is shown, never blocks it |
| any | failed | finish | the failure is stored on the message, as today |
| any | stopped | finish | status `cancelled` |

There is no separate **plan** node. A plan is an extra model call before every answer. On a local model at 0.3 to 20 tokens a second that is seconds to minutes, for a gain nobody has measured on small models. Cloud runs get planning through the notes tool (section 4).

Interrupts follow LangGraph's rule (Verified): code that runs before an interrupt runs again on resume, so side effects before it must be idempotent. Here the interrupt sits between `act` deciding a call needs approval and the call running. Nothing has run yet when the run stops.

### 1.3 Checkpoints

The loop saves `AgentRunRecord` and the message at step boundaries only, never per token:

- when the run starts (status `running`, node `assemble`)
- when a round of `generate` ends (round text into `roundTexts`)
- when a tool call gets its result
- when the run stops for approval (status `awaitingApproval`)
- when the run finishes, fails or is cancelled

Before G2 adds the run table, G1 closes fact 6 with a marker. `startStream` sets `failure = .interrupted` (a new `ReplyFailure.Kind`; older builds decode it as `unknown`) on the assistant message when it inserts it, and `finish()` clears it or replaces it with the real failure. A kill leaves the marker in place, so no launch heuristic is needed and old replies saved before `metadataData` existed are never flagged. The chat ignores the failure on the one message that is streaming now.

After G2, on launch, one sweep reads every run record that is not `finished`, `failed` or `cancelled`:

| Status at launch | What the user sees | Why |
|---|---|---|
| `running`, any engine | The reply shows its partial text and the failure "The reply stopped when the app closed." with Retry. Status becomes `interrupted`. | Generation needs the model and the app in the foreground. Silently restarting a cloud request costs money. |
| `awaitingApproval`, cloud or local | The inline approval card from D27 comes back on its step. Allow or Deny continues the run from `act`. | The app owns the cloud and local loops, so it can rebuild the transcript from `roundTexts` and the stored steps. |
| `awaitingApproval`, Apple | The card comes back. On Allow, the tool runs and the app starts a new Apple turn whose prompt holds the earlier text and the tool result as text. | Apple's framework loop cannot be re-entered. Building `Transcript.ToolCalls` entries by hand is not documented (Verified: the Transcript page lists no initializers for tool entries). |

Resume rules for each tool step, after LangGraph's "make pre-interrupt side effects idempotent" and "re-check external state after long pauses" (Verified):

- A step with a result is never run again.
- A step waiting for approval asks again.
- A read step (`BuiltInTool` reads, `web_search`, read-only MCP tools) that was approved but has no result runs again.
- A write or external step (LA1 classes `write`, `external`) that was approved but has no result does not run again. The row says "This may not have finished. Check, then try again." The model is not told it ran.

### 1.4 How each engine plugs in

The app loop needs one call from each engine: run one round and report what the model asked for, without running it.

```swift
/// One model round. The engine streams text and reasoning and proposes calls; the app loop runs them.
protocol StepFunction: Sendable {
    func step(model: ModelDescriptor, prompt: AssembledPrompt, tools: [ToolSpec], toolsOn: Bool)
        -> AsyncThrowingStream<StepEvent, Error>
}

enum StepEvent: Sendable { case text(String), reasoning(String), proposed(ToolCall),
                           usage(prompt: Int, completion: Int), metadata(ResponseMetadata), end(finishReason: String?) }
```

| Engine | Step function | Loop owner | What it costs to change |
|---|---|---|---|
| AnyRouter | `AnyRouterEngine.streamRound` already is one round. Wrap it. | app loop | Delete the `while true` loop in `stream(tools:)`. |
| GGUF, MLX | one `base.stream` plus `LocalToolParser`, already one round of `LocalToolEngine.run` | app loop | Delete `LocalToolEngine.run`. Keep `LocalToolFormat` and `LocalToolParser`. |
| Apple | none | the framework | Keep `AppleFoundationEngine.stream(tools:)`. The app loop passes it a `ToolHost` that saves the run before and after each `execute`. The run then has the same rows and checkpoints, and the resume rule above. |

**Conflict with D24 and local-agent.md.** Both say to keep the engine-owned loop with host-owned approval. This design moves the loop into the app for cloud and local. The reason is resume. A run that waits for approval across a relaunch needs its transcript and round count outside the engine's stream. The host still owns approval and execution, so the single confirmation hook that WWDC26 347 asks for stays in one place. `ToolRunScope` stays for cancellation. Apple keeps the engine-owned loop. If the operator prefers not to move the loop, the fallback is units G1 and G2 only: the launch sweep and checkpoints, with an interrupted run always shown as a failure.

## 2. Memory

### 2.1 What is remembered

```swift
/// Core/MemoryRecord.swift (new, lane A reviews). Additive to ModelContainer.anyRouter.
@Model final class MemoryRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String          // MemoryKind
    var text: String             // one short statement, at most 280 characters; a chat summary at most 600
    var originRaw: String        // MemoryOrigin
    var scopeRaw: String         // MemoryScope: where the content came from, which decides where it may go
    var sourceThreadID: UUID?
    var sourceMessageID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int = 0
    /// Later (unit M7), only with consent. Nil until then.
    var embedding: Data?
    var embeddingModel: String?
}

enum MemoryKind: String, Codable { case profile, preference, fact, note, chatSummary }
enum MemoryOrigin: String, Codable { case typedInSettings, askedInChat, extracted, modelTool }
enum MemoryScope: String, Codable { case everywhere, deviceOnly }
```

- **profile**: who the user is. "My name is Lan." "I live in Ho Chi Minh City."
- **preference**: how the user wants answers. "Answer in Vietnamese." "Short answers."
- **fact**: something the user stated that is not about how to answer. "My dog is called Mochi."
- **note**: text the user pinned by hand in Settings or from a message's menu ("Remember this").
- **chatSummary**: one per chat, for `search_chats`. Built from the newest compaction summary when there is one, else from the title and a short summary (section 2.3).

Profile, preference and note items make the **always-on profile**. Facts and chat summaries are recalled when they match.

### 2.2 Where it lives

- SwiftData, on the device, in the same store as the chats. Nothing syncs (cloud sync is out of scope for v1).
- No embeddings in the first units. Lexical search is enough for a few hundred short items, and Hermes uses plain FTS5 for its session search with no model call (Verified).
- Embeddings later, behind the consent rules in 2.6. On device: `NLContextualEmbedding` (iOS 17, assets downloaded with `requestAssets`; dimension, sequence length and languages are read at run time because the docs give no numbers, Verified). Cloud: an AnyRouter embedding model, only for items whose scope is `everywhere`, only after consent. Whether AnyRouter serves embeddings is open question 3.

### 2.3 How memories are written

| Path | Engines | Model call | When | Phone cost |
|---|---|---|---|---|
| Typed in **Settings › Memory** | all | none | any time | none |
| "Remember that ..." in the chat | all | none | the user's message matches a pure classifier: "remember that", "from now on", "my name is", "I'm allergic to", and the Vietnamese "nhớ rằng", "từ giờ", "tên tôi là". The sentence is saved without the cue phrase ("Remember that I'm vegetarian" saves "I'm vegetarian"). | a regex pass, under 1 ms (Inferred) |
| "Remember this" on a message | all | none | a context-menu action on any message | none |
| Extraction after the reply | Apple | one guided-generation call with a `@Generable` list of at most 3 candidates | after the reply, in the foreground, only when the user's message has a first-person statement (same classifier, looser) | a few seconds on Apple (Inferred). Off on GGUF and MLX: a second generation at 0.3 to 20 tokens a second blocks the one loaded model (`LocalResidency`) |
| `memory` tool | cloud | inside the run | the model decides, as in Hermes (Verified) | none on the phone |
| Chat summary | all | one summary call, by the D30 rule: Apple on device when ready, else the chat's own model, never a cloud model for a device chat | when a chat with at least 6 messages loses focus, and only if no compaction summary exists | one extra short generation per chat. On GGUF and MLX use the compaction summary only, never an extra call |

Every write shows one `TraceRow` in the reply (D27), not a new view: "Memory updated", with the saved text on expand and **Undo** and **Edit**. A write that fails the cap or duplicates an item says so in the same row.

Caps follow Hermes, which keeps memory to 2,200 plus 1,375 characters and refuses a write past the cap instead of compacting (Verified). Here the cap is 60 items of kinds profile, preference and note, and 500 facts. A write past a cap is refused with a message that names the oldest unused items. Nothing is removed without the user.

### 2.4 How memories are found

**Always-on profile.** Profile, preference and note items rendered as one short list after the stable instructions. Order: pinned notes, then preferences, then profile items, newest first within each kind. Items are added whole until the engine's profile budget (3.3, counted with 3.1) is spent. An item that does not fit is left out of that request, never cut in the middle. The rendered list is frozen when a chat sends its first message and stored as `ThreadRecord.profileSnapshot: String?`, as Hermes freezes its memory snapshot to keep the prompt cache (Verified). A relaunch reads the snapshot, so the prefix does not change. A memory saved during the chat is already in that chat's messages, so the model knows it. Edits in Settings apply from the next chat.

**Recall on Apple and local models: before the send, in the app.** `WebGrounding` (T15) is the precedent: the app decides, runs the lookup and puts the result in front of the question for that request only. For memory:

1. Score facts and chat summaries against the user's last message with a lexical scorer (BM25 over folded, diacritic-insensitive words; Vietnamese is folded with `.diacriticInsensitive`).
2. Keep the top 3 above a score floor, within the engine's hit budget. An exact match scores above a match found only after folding, because folding merges Vietnamese words that differ only by a tone mark.
3. Put them just before the last user message, as "Things the user told you before:" with one line each.
4. Record them in `AgentState.memoryHits`. The reply footer shows "Used 2 memories", which expands to the items.

Apple's own advice is to run a lookup yourself and put its result in the prompt when the data is always needed (TN3193, Verified). This also keeps the 4-tool window for the clock, calculator, search and page reader.

**Recall on cloud models: tools, just in time.** Anthropic's context-engineering guidance is to keep references and load content with tools when needed (Verified). Cloud models get the same pre-send hits as device models, plus:

- `memory`: one tool with an `action` argument: `search`, `add`, `patch`, `remove`. This follows Hermes, whose memory tool has `add`, `patch`, `remove` and a `target` (Verified). One tool costs one schema. Anthropic's memory tool exposes file commands (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`, Known); file paths add nothing for short items.
- `search_chats`: query in, at most 5 results out (chat title, date, chat summary, and one matching message cut to 300 characters).

`search_chats` is the recall tool of LA16. Its first backend is a lexical scan of the store: `#Predicate` with `localizedStandardContains` per query word, at most 200 candidate messages, scored in Swift. The Core Spotlight index of LA16 becomes its second backend when LA16 lands. That index puts chat text into the system's Spotlight index, so it needs its own switch. It is not a second index for this design.

### 2.5 What the user sees and controls

**Settings › Memory** plugs in through D20: a `SettingsDestination` case, a page in `Features/Settings/Pages/MemorySettings.swift`, a stock `Form`.

- **Use memory** (on by default). Off means no profile, no recall, no writes, and the memory tools are not offered.
- **Save memories automatically** (on by default). Off means only typed items, "Remember that" and "Remember this" are saved.
- **Use memories from on-device chats in cloud chats** (off by default). See 2.6.
- A list grouped by kind: About you, Preferences, Pinned notes, Facts, Chat summaries. Each row shows the text and where it came from ("From the chat Trip to Da Lat"). Tap to edit. Swipe to delete. **Add** in the toolbar.
- **Delete all memories**, with a confirmation dialog.
- One line under the profile items says how many of them the on-device Apple model gets ("Apple Intelligence sees the first 6"), computed with the 3.3 budget.

In the chat:

- The "Memory updated" row with Undo and Edit (section 2.3).
- "Used 2 memories" in the reply footer, expanding to the items, each with **Forget**.
- A chat's More menu gets **Don't use memory in this chat**, stored as `ThreadRecord.memoryOff: Bool = false`.

### 2.6 Privacy rules

A **device chat** is a chat whose reply came from Apple, GGUF or MLX. A **cloud chat** reply came from AnyRouter. A memory's scope is set when it is written: `deviceOnly` when it came from a device chat, `everywhere` when it came from a cloud chat or was typed in Settings (the page says typed items go to the model you chat with).

| Rule | Device chat | Cloud chat |
|---|---|---|
| Profile and recalled items in the prompt | all items | `everywhere` items. `deviceOnly` items only when the cross switch is on. |
| `search_chats` scope | n/a on device (no tool); pre-send recall reads all chats | cloud chats only, unless the cross switch is on |
| Who extracts and summarizes | the device (D30) | the chat's own model, which already has the text |
| Embeddings | on device only | on device, or AnyRouter for `everywhere` items after consent |
| First time a `deviceOnly` item goes to a cloud model | | one notice in the chat, like LA9's notice for sensitive tool results |

A test asserts the cloud rule on the request body (eval E8).

## 3. Context engineering per engine

### 3.1 Count tokens honestly first

| Engine | Counter | Source |
|---|---|---|
| Apple | `SystemLanguageModel.tokenCount(for:)` for instructions, prompts and tools on iOS 26.4 and later; `contextSize` for the window | Verified: `contextSize` is back-deployed before 26.4; `tokenCount(for:)` is named in the context-window article |
| GGUF | `llama_tokenize` of the loaded model, which the engine already calls | Code |
| MLX | the model's tokenizer (`TransformersTokenizer`) | Code |
| Cloud, and the fallback everywhere | characters divided by 3 for Latin text without diacritics, characters divided by 1 for CJK and Vietnamese, rounded up | Verified ratios from Apple's article; one rule for every engine because the cloud tokenizer is not known |

The fallback replaces `CompactionLogic.tokens`. It overcounts English by up to a third, which is the safe side for a 4k window.

### 3.2 The prompt assembler

One pure function builds every request: `PromptAssembler.assemble(input, budget) -> AssembledPrompt`. It replaces `CompactionLogic.systemPrompt`, the prompt pieces in `startStream` and `WebGrounding.applying`. Sections, in the order they are sent:

| # | Section | Changes | Goes in |
|---|---|---|---|
| 1 | App instructions, custom instructions, tool guidance (`AppleToolGuidance` or the local tool format) | rarely | system message |
| 2 | Always-on profile, frozen per chat | per chat | system message |
| 3 | Skills index (cloud only) | per app version | system message |
| 4 | Tool specs (`ToolProfile.shaped`) | per chat, when the tool switches change | the engine's tool field, or the system message on local |
| 5 | Compaction summary | per compaction | text in front of the first user message of the recent turns |
| 6 | Recent turns | per turn, append only | messages |
| 7 | Memory hits, web grounding, @ mentions | per turn | text in front of the last user message, for this request only, as `WebGrounding.applying` does today |
| 8 | Notes (cloud runs with notes) | per round | after the last tool result |
| 9 | Tool calls and results of this run | per round | messages, clipped (3.4) |

Rules:

- Sections 1 to 4 are the stable prefix. No time, no date, no counters in them. The date comes from the clock tool. Manus calls a timestamp at the start of the prompt the classic cache breaker (Verified).
- Turns are appended, never edited. A compaction is the only edit, and it moves only section 5 and the start of section 6.
- The summary leaves the system message. Today every compaction changes the system prompt (fact 5).
- No section adds a message of its own. Sections 5 and 7 are merged into the text of a user message, so roles still alternate. Gemma-style templates reject two user messages in a row, and this repo renders GGUF templates with Jinja and its own Gemma 4 formatter.
- Tool specs are sent in one fixed order: the `ToolProfile` rank, then the name.
- The assembler returns `used: [PromptSection: Int]`. The D27 context meter reads it instead of its own estimate.
- On Apple the prompt is still one string (`ApplePrompt`). Sections 1 to 4 go to `instructions`, 5 to 9 to the prompt.

### 3.3 Budgets

Numbers are starting points in tokens. Each one is checked with the counter from 3.1, and the eval suite fails when a section goes over.

| Section | Apple, 4,096 | Local, 4,096 (streamed tier) | Local, 8,192 (`FitPlanner.maxContext`) | Cloud, 128k and more |
|---|---|---|---|---|
| Output reserve | 700 | 700 | 1,024 | the model's `max_tokens`, default 8,000 |
| Instructions and tool guidance | 300 | 400 | 400 | 2,000 |
| Tool specs | 4 tools, measured (about 350) | 4 tools (about 450) | 4 tools (about 450) | all enabled, measured |
| Profile | 120 | 120 | 200 | 500 |
| Skills index | 0 | 0 | 0 | 1,500 |
| One matched skill's steps (device only, in this turn's context) | 250 | 250 | 400 | 0 (the index and `read_skill`) |
| Compaction summary | 300 | 300 | 400 | 2,500 |
| Memory hits | 150 (3 items) | 150 | 300 | 1,500 |
| Notes | 0 | 0 | 0 | 500 |
| One tool result | the smaller of 400 tokens and a third of what is left | same | the smaller of 800 tokens and a third of what is left | 20,000 characters, about 5,000 tokens (today's cap) |
| Recent turns and this run | the rest, about 2,100 | about 1,900 | about 5,400 | the rest |
| Compaction trigger | used above 80% of window minus reserve | same | same | the smaller of 80% of the window and 64,000 |

Why these numbers:

- Apple: TN3193 says 3 to 5 tools with descriptions of a short phrase, and prompts of 1 to 3 paragraphs (Verified). local-agent.md proposed about 1,500 characters per tool result for Apple, against today's 6,000.
- Profile at 120 tokens is about 10 short English items, or 3 to 4 in Vietnamese at one token per character. That is why the profile is filled in priority order and items are never cut.
- 400 tokens per result is about 1,500 English characters, the figure local-agent.md proposed for Apple. Caps are in tokens so Vietnamese pages are not three times over.
- Cloud trigger at 64,000: input tokens are most of an agent's cost (Manus measured about 100 input tokens per output token, Verified). A cheaper prompt beats a full one for chat. This is a choice, not a measurement. Measure cost per reply before and after.

### 3.4 Clearing tool results inside a run

Across turns nothing is replayed (fact 1). Inside a run:

- **Cap from what is left.** Before each round, `act` clips each new result to the budget's per-result limit, computed from what is left in the window. This fixes fact 2.
- **Clear old results to a stub.** When the next round would not fit, results older than the newest 3 become one line: "[Result cleared: fetch_url https://example.com/page, 4,210 characters]". This follows Anthropic's tool-result clearing (default keeps 3 tool uses, Verified) and Manus's rule that compression must be restorable: the URL stays, so the model can fetch it again (Verified). Hermes stubs results over 200 characters outside its tail (Verified).
- **Clear in large steps on cloud.** Each clearing breaks the provider's prompt cache from that point. Clear only when it frees at least 8,000 tokens, like Anthropic's `clear_at_least` (Verified).
- **Errors stay.** A failed call and its error text are cleared last. Manus found that leaving failed actions in context stops the model repeating them (Verified).
- **Never split a call from its result.** pi never cuts between a tool call and its result (Verified). The cloud API rejects a tool message without its call.

What carries to the next turn: a **tool digest**, one line per call, appended to the text of every assistant message that used tools, on every request: "Searched the web for 'Da Lat weather'. Read https://example.com/page." The assembler derives it from the stored `toolSteps` the same way each time, so a turn's text never changes after it is sent and the prefix stays append only. At most 40 tokens per reply on Apple and local; old replies leave with compaction like any text. It lets a follow-up such as "read the second page again" work without replaying results. This bends T3 (steps not replayed): the digest is a summary line, not the result.

### 3.5 Compaction

The trigger, the fold and the stored `Compaction` stay as `CompactionLogic` has them, with three changes:

1. The trigger uses the assembler's real count and the budget in 3.3, not the byte estimate.
2. The cloud summary uses fixed headings, after pi: Goal, Constraints and preferences, Progress, Key decisions, Next steps, Critical context (Verified). Apple and local keep the plain prompt, since headings cost tokens they do not have.
3. What survives without being summarized: the profile (re-sent every request), memory hits (recalled again), the notes (on the thread), the newest exchanges (`keepRecentAutomatic` = 4), and the tool digests of the kept replies. The summary never needs to repeat a memory item.

On Apple, `LanguageModelError.contextSizeExceeded` (the older name is `GenerationError.exceededContextWindowSize`, now deprecated, Verified) is mapped to `ReplyFailure.Kind.contextTooLong`, compacts once and retries once. A second failure shows **Shorten chat**.

### 3.6 Where a stable prefix pays

| Engine | Pays today? | When it pays |
|---|---|---|
| AnyRouter | Where the upstream provider caches prefixes. Manus measured cached input at a tenth of the price on Claude Sonnet (Verified). Hermes keeps its system prompt fixed for the same reason (Verified). | Now. Measure cached tokens if the usage block reports them (unverified for AnyRouter). |
| GGUF | No. A new context per answer (fact 5). | After F3: keep the context and its KV between turns of the same chat, and evaluate only the new suffix. A stable prefix is what makes the suffix short. |
| MLX | No. Fixed rotating `maxKVSize` of 4,096. | After S7 replaces it; then the same as GGUF. |
| Apple | No. A new session per reply. | Only if the app keeps one `LanguageModelSession` per open chat and calls `respond` for each new message. Then the framework keeps the transcript, and `ApplePrompt`'s flattening goes away. Try it as a measured experiment after A2, with `prewarm` on chat open (Known). |

## 4. Techniques from pi, Hermes and others

| Technique | From | Take? | Engines | Phone cost | Why |
|---|---|---|---|---|---|
| Small prompt and few tools | pi: prompt and tool definitions under 1,000 tokens, 4 tools (Verified) | Yes, already | all | saves tokens | `ToolProfile` caps device models at 4. Measure section 1 of the prompt per engine in the eval report. |
| Tools as on-demand docs instead of MCP | pi: Playwright MCP is 21 tools and 13.7k tokens (Verified) | Partly | cloud | none | Cloud gets every enabled tool today. Report the tool-spec tokens; if they pass 8,000, rank and cap cloud tools too. |
| Frozen memory snapshot | Hermes (Verified) | Yes | all | none | Keeps the prefix stable for the cache and for F3. |
| Hard memory caps, no silent compaction | Hermes (Verified) | Yes | all | none | The user owns the list. |
| Session search with no model call | Hermes FTS5 (Verified) | Yes | all | a fetch and scoring, milliseconds for thousands of messages (Inferred, measure) | `search_chats` and pre-send recall. |
| Memory as tools | Anthropic memory tool, Hermes (Verified) | Cloud only | cloud | none | Device models recall in the app (2.4). |
| Just-in-time retrieval | Anthropic (Verified) | Yes | all | as above | Cloud through tools, device through pre-send recall. |
| Structured compaction summary | pi (Verified) | Cloud only | cloud | none | Headings cost tokens a 4k model does not have. |
| Tool-result clearing | Anthropic, Hermes (Verified) | Yes, inside a run | all | none | Section 3.4. |
| Stable prefix, append only | Manus (Verified) | Yes | all | none | Section 3.2. |
| Mask tools instead of removing them | Manus (Verified) | No | | | Needs logit masking. The cloud API has none; llama.cpp grammars could, but D14 rules out building more of `common/` for this. Keep the rule's spirit: the tool list does not change inside a run. |
| Keep errors in context | Manus (Verified) | Yes, already | all | none | Results with `isError` go back today. Clear them last (3.4). |
| Todo recitation | Manus: about 50 calls per task (Verified). pi: todo lists confuse models (Verified). | Cloud only, runs of 3 rounds or more | cloud | none | A `notes` tool that replaces a list of at most 10 items, recited after the last tool result. Device runs are 4 rounds at most, too short to drift. |
| Vary serialization to avoid a few-shot rut | Manus (Verified) | No | | | Chat runs are short. Low value. |
| Session tree and fork | pi `/tree`, `/fork` with branch summaries (Verified for commands and summaries; file format unverified) | Not now | | UI work | Regenerate covers the common case. Revisit with a "Branch from here" request. |
| Self-written skills | Hermes `skill_manage` (Verified) | Later, cloud only, with approval | cloud | none | Unit K2. |
| Skills with progressive disclosure | pi and Hermes: only name and description in the prompt, the body read on demand; Hermes's level-0 list is about 3k tokens (Verified) | Later, cloud only | cloud | none | A 4k model cannot pay for an index. |
| Sub-agents for research | Anthropic: condensed results of about 1,000 to 2,000 tokens (Verified). pi: "a black box within a black box" (Verified). | Cloud only, as designed in D25 unit 5 | cloud | none | `LocalResidency` allows one loaded local model, so a local sub-agent would queue behind its parent. A cloud sub-agent from a device chat would send device text to the cloud. |
| Escalation to a cloud model | | Yes, as a button | device to cloud | none | Section 4.1. |
| Background review of a session | Hermes (Verified) | No on device | | battery, and the loaded model | Maybe later for cloud chats. |
| Checkpoint per step, interrupts | LangGraph: a checkpoint per super-step, `StateSnapshot` with `next` and `parent_config`, resume with `Command(resume:)` (Verified) | The shape, not the library | all | one SwiftData save per step | LangGraph is Python and JavaScript. Section 1. |

### 4.1 Escalation from a device model to a cloud model

- A device reply that failed with `contextTooLong` or `localOutOfMemory`, or any device reply through its menu, offers **Ask a cloud model**. It opens the model picker filtered to cloud models.
- The first time per chat, a notice says the chat's text will go to AnyRouter. It names the model, as LA9 does for sensitive results.
- The chat continues with a "Switched to" note (`SwitchNotes` exists). From that reply on, the chat counts as a cloud chat for 2.6.
- Never automatic. D30 already rules out a cloud model for a device chat's title.

### 4.2 Skills

Skills need the operator's go-ahead (open question 4). If yes:

- K1, read only: SKILL.md files bundled in the app (name, description, body, optional reference files). Cloud models get the index (at most 1,500 tokens) and a `read_skill` tool. Apple and local get no index and no `read_skill`: before the send the app picks at most one enabled skill whose name and description share two content words with the question (the words of memory recall), and puts its steps in this turn's context when they fit the device skills budget in 3.3. The text says it is guidance and allows no tool.
- K2, written by the agent: after a cloud run with at least 3 tool calls that ended well, the model may call `propose_skill`. The user sees an approval card with the full text. **Settings › Skills** lists, edits and deletes skills. Hermes asks skills to keep "lessons, not logs" (Verified). The approval card is the only path to save, because a skill is instructions that later runs obey.

## 5. Evals

### 5.1 Scripted suite (CI, every push)

Extend `ScriptedEngine` into a `RecordingEngine` that keeps every request it receives: messages, system prompt, tool specs. Cloud tests capture the `URLRequest` body through the stubbed `URLSession` that the AnyRouter tests already use. Scenarios join `AgentLoopScenarioTests`.

| Id | Scenario | Passes when |
|---|---|---|
| E1 | Memory recall across chats. Chat A: "I'm vegetarian, remember that." Chat B, new thread: "Dinner idea?" | A `MemoryRecord` exists after A. B's request holds the item before the last user message. B's footer data lists one memory. |
| E2 | Stable prefix. Two turns in one chat, a memory saved between them, then a relaunch. | Sections 1 to 4 are byte-identical across all three requests, and so is the text of every earlier turn. |
| E3 | Long chat beyond the window. 200 mixed English and Vietnamese turns on the Apple budget. | Every request is under window minus reserve by the counter in 3.1. The profile is in every request. One summary exists. No `contextTooLong`. |
| E4 | Local loop overflow. 4 rounds, each returning 6,000 characters, at 8,192 tokens. | Every round's request fits. Results older than 3 are stubs with their URL. |
| E5 | Tool failure recovery. The first call fails, the scripted model retries with other arguments, then the same failing call repeats. | The error text is in round 2. The loop stops on the repeated identical call. |
| E6 | Approval and resume. A cloud run reaches `awaitingApproval`. The test opens a new `ModelContainer` on the same store URL and a new view model. | The card is back on its step. Allow runs the tool exactly once (a counter). The reply finishes with the result in round 2's request. |
| E7 | Kill during generate. The record is saved as `running` with partial text. | After the launch sweep the message has the failure "interrupted" and Retry. Retry replaces it. |
| E8 | Privacy. A `deviceOnly` memory and a cloud chat. | The cloud request body never holds the item text with the cross switch off, and holds it with the switch on. |
| E9 | No repeat of a write. An approved write step with no result at relaunch. | The tool's run counter stays at 0. The row asks the user to check. |
| E10 | Delete. "Forget" in the footer and **Delete all** in Settings. | The item is gone from the store and from the next request. |

### 5.2 Live suite

- LA11's tool-calling set (about 20 prompts per engine) runs in `model-smoke.yml` for GGUF and on device for Apple and MLX, like `apple-tool-evals.json`.
- Add a memory set of 10 prompts per engine, from a fixed fixture of 30 memories: 5 that should be recalled, 3 traps that look similar and should not, 2 explicit "remember that" saves.
- A judge model scores "used the right memory" and "invented a memory" (same AnyRouter judge and secret as F8c, two runs, report the spread).

### 5.3 Metrics

| Metric | How | Target to start |
|---|---|---|
| Recall at 3 | scripted fixture, lexical scorer | 0.9 or better, else add embeddings (M7) |
| Wrong recalls | trap memories in the top 3 | under 1 in 10 prompts |
| Extraction precision | saved items judged correct, per 100 turns of the live set | under 2 false saves |
| Budget overflows | `contextTooLong` in scripted runs; the failure kind's rate in telemetry | 0 scripted |
| Prefix stability | share of turns whose sections 1 to 3 match the previous turn. Tool specs (section 4) change by design with an @ mention, a photo (`ocr_image`) or going offline; those turns are counted apart as expected misses | 95% or more |
| Cost per cloud reply | prompt tokens and cost from `ResponseMetadata`, before and after A2 and A3 | lower, with E1 and E3 passing |
| Assembler time | p95 of `assemble` plus recall, with 5,000 stored messages, on the operator's iPhone | under 30 ms (measure on device; the Simulator is not a device number) |
| Resume success | E6 and E7, then device checks of the approval card after a kill | all pass |

Before trusting a number, follow PLAN's Measuring rule: same prompts, same model, cold and warm runs, thermal state recorded.

## 6. Phased plan

Each unit is one push to main that ends in a green CI run. Sizes: S is under 200 changed lines, M is 200 to 500, L is over 500. "Core" marks a unit that touches `Core/` and needs lane A's review. No unit needs a local build; CI is the gate (AGENTS.md).

Memory first, because the user sees it on day one. A1 comes right after M1, because M2 and M4 put text in the prompt under token caps and their checks need the real counter.

| Unit | What | Size | Core | Check |
|---|---|---|---|---|
| M1 | `MemoryRecord`, `MemoryStore` (add, edit, delete, caps, scope), **Settings › Memory** page with the three switches | M | yes | store unit tests; a UI test adds, edits and deletes an item; accessibility audit passes |
| A1 | Token counter from 3.1 replaces `CompactionLogic.tokens` | S | no | tests for English, Vietnamese and Chinese strings; Apple counter behind `#available(iOS 26.4, *)` |
| M2 | Always-on profile in the prompt, filled in priority order, frozen in `ThreadRecord.profileSnapshot`; **Don't use memory in this chat** (`ThreadRecord.memoryOff`) | S | yes | E2, and a test that the profile is absent with the switch off |
| M3 | "Remember that" classifier (English, Vietnamese), "Remember this" message action, "Memory updated" `TraceRow` with Undo and Edit | M | no | classifier tests per language; E1 save half; UI test for Undo |
| M4 | Pre-send recall: lexical scorer, top 3 in front of the last message, "Used N memories" in the footer with Forget | M | no | E1, E10; scorer tests with diacritics |
| M5 | Cloud `memory` tool and `search_chats` (lexical backend), scope rules | M | no | E8; `AnyRouterToolLoopTests` with the tool |
| M6 | Chat summaries by the D30 rule; Apple extraction after the reply | M | no | tests with `ScriptedEngine`; Apple path covered by `apple-tool-evals.json` style on-device list |
| A2 | `PromptAssembler` with sections and budgets; summary out of the system message; the context meter reads its report | L | no | E2, E3; existing `CompactionTests` and `CompactionChatTests` still pass |
| A3 | In-run result caps from the remaining budget, stubs for old results, tool digest for the next turn | M | no | E4, E5 |
| A4 | Structured cloud summary; compact-once-and-retry on Apple's context error | S | no | `CompactionTests` for both prompts; a scripted Apple failure test |
| G1 | The `interrupted` marker set at insert and cleared in `finish()` (1.3). Needs no new table. | S | no | E7 with a store URL; extend `UITests/ReplyFailureTests.swift` |
| G2 | `AgentRunRecord` and saves at step boundaries; G1 reads it | M | yes | a test kills after each boundary and checks the stored node |
| G3 | `StepFunction` for AnyRouter and local; one app loop; delete the `AnyRouterEngine` loop and `LocalToolEngine.run` | L | no | `AgentLoopScenarioTests`, `AnyRouterToolLoopTests`, `LocalToolTests` unchanged and green |
| G4 | Approval interrupt saved and resumed; `ToolStep.approval`; the resume rules of 1.3 | M | yes | E6, E9 |
| G5 | `notes` tool and recitation, cloud only, on `ThreadRecord.notesData` | M | yes | a scripted 5-round run shows the notes after the last result each round |
| X1 | **Ask a cloud model** on device replies, with the notice | S | no | UI test from a `contextTooLong` reply |
| K1 | Bundled skills, index and `read_skill`, cloud only (needs open question 4) | M | no | index token count under 1,500; scripted read |
| K2 | `propose_skill` with the approval card, **Settings › Skills** | M | yes | approval UI test; nothing saves on Deny |
| L1 | Live memory set and judge in `model-smoke.yml` and the on-device list | M | no | report artifact with the 5.3 metrics |
| M7 | Embeddings behind consent, only if recall at 3 is under 0.9 | M | yes | recall at 3 on the same fixture, before and after |
| S1 | Sub-agents per D25 unit 5, after G3 | L | no | its own plan in PLAN.md |

G1 has no dependency and can ship any day. It closes the hole in fact 6.

## 7. Open questions for the operator

1. **Device memories in cloud chats.** Should items learned in on-device chats reach cloud models? This design says no unless the user turns on the switch.
2. **Automatic saves.** Should the agent save memories without asking (Hermes's default, with Undo in the row), or ask before each save?
3. **Embeddings.** Does AnyRouter serve an embedding model the app may call with the sign-in key? If not, embeddings stay on device or wait.
4. **Skills.** Skills are out of scope for v1 in PLAN.md. Is K1 (bundled, read only) wanted now, and K2 (written by the agent, approved by the user) later?
5. **Loop ownership.** Is moving the cloud and local loops into the app (G3) acceptable against D24? Without it, an interrupted run can only show a failure, never resume.

## Sources

Code (AnyRouterApp at `1b61f52`): `Core/Records.swift`, `Core/Contract.swift`, `Core/Tools.swift`, `Features/Chat/ChatViewModel.swift` (`startStream`, `finish`), `Features/Chat/CompactionLogic.swift`, `Features/Chat/SubagentLogic.swift`, `Features/Chat/ReplyFailureLogic.swift`, `Engines/Tools/AgentToolHost.swift`, `Engines/Tools/BuiltInTool.swift`, `Engines/Tools/ToolProfile.swift`, `Engines/Tools/ToolContext.swift`, `Engines/Apple/AppleFoundationEngine.swift`, `Engines/Apple/ApplePrompt.swift`, `Engines/Apple/AppleDynamicTool.swift`, `Engines/Apple/AppleToolRunLogic.swift`, `Engines/Local/Tools/LocalToolEngine.swift`, `Engines/AnyRouter/AnyRouterEngine.swift`, `Engines/MCP/MCPToolHost.swift`, `docs/research/local-agent.md`, PLAN.md sections D20, D24, D25, D27, D29, D30, T3, T15, LA1 to LA16, F3, S6, S7.

Web (fetched 2026-11-27):

- pi: https://mariozechner.at/posts/2025-11-30-pi-coding-agent/ (prompt and tools under 1,000 tokens, 4 tools, no MCP, no sub-agents, todos), https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/compaction.md (reserve 16,384, keep 20,000, summary headings, never cut at a tool result, branch summaries), https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md (name, description and path in the prompt, body on demand), https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/usage.md (`/tree`, `/fork`). The session file format was not found (404) and is unverified.
- Hermes agent: https://github.com/NousResearch/hermes-agent, https://hermes-agent.nousresearch.com/docs/user-guide/features/memory (2,200 and 1,375 characters, frozen snapshot, add, patch, remove, FTS5 session search), https://hermes-agent.nousresearch.com/docs/user-guide/features/skills (three levels, `skill_manage`, "lessons, not logs"), https://hermes-agent.nousresearch.com/docs/developer-guide/context-compression-and-caching (50% trigger, tool output stubs over 200 characters, stable system prompt).
- LangGraph: https://docs.langchain.com/oss/python/langgraph/persistence, https://docs.langchain.com/oss/python/langgraph/checkpointers (`StateSnapshot` fields, pending writes, replay), https://docs.langchain.com/oss/python/langgraph/interrupts (resume re-runs the node, idempotent side effects), https://docs.langchain.com/oss/python/langgraph/add-memory (store namespaces, semantic search).
- Anthropic: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents, https://www.anthropic.com/engineering/building-effective-agents, https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool, https://platform.claude.com/docs/en/build-with-claude/context-editing (keep 3 tool uses, `clear_at_least`, cache interaction).
- Manus: https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus (10x cached price, 100:1 input to output, about 50 calls per task).
- Apple: https://developer.apple.com/documentation/foundationmodels/managing-the-context-window (4,096 tokens, token ratios, what counts, `contextSizeExceeded`, transcript recovery), https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window (3 to 5 tools, run the lookup yourself, retrieval), https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize, https://developer.apple.com/documentation/foundationmodels/transcript, https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding.
