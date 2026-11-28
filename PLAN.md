# PLAN.md: AnyRouter for iPhone and iPad

This file holds the latest state only. When a task is done, delete its line and update the current state. History lives in git.

## Goal

A native SwiftUI app **AnyRouter** for iPhone and iPad. It follows a reference mobile chat UI and UX (own AnyRouter branding) and chats with:

1. **Apple Foundation Models**, on device
2. **Local Hugging Face models**, GGUF (llama.cpp) and MLX, from a configurable catalog
3. **AnyRouter models**, after **Sign in with AnyRouter** (OAuth + PKCE)

Milestone 1 is a TestFlight internal build on the operator's own iPhone and iPad. The upload path is untested until Q1 and Q2 are answered.

## Decisions

| # | Decision |
|---|---|
| D1 | Native SwiftUI, not the Tauri fork. The look follows the reference design, written natively. |
| D2 | Public repo `AnyRouterHQ/AnyRouterApp`, Apache-2.0. Public also gives free macOS CI minutes. |
| D3 | GGUF (llama.cpp) and MLX both sit behind one `ChatEngine` protocol. |
| D4 | Milestone 1 is a TestFlight internal build with automatic signing and an App Store Connect API key (4 secrets and an app record, see Q1 and Q2). |
| D5 | iOS and iPadOS 26.0 minimum, one universal target. FoundationModels needs 26. |
| D6 | Bundle id `oneni.anyr.app`, display name `AnyRouter`. The family is `oneni.anyr.*`. |
| D7 | XcodeGen `project.yml`, no committed `.xcodeproj`. Parallel work adds files without pbxproj conflicts. |
| D8 | CI on GitHub Actions macOS runners is the only build. The operator Mac has no Xcode and a no-local-build rule. |
| D9 | OAuth: dynamic client registration (`/api/v1/mcp/oauth/register`), PKCE, loopback `127.0.0.1` callback through `ASWebAuthenticationSession`. The server rejects custom URL schemes. |
| D10 | SwiftData for threads and messages, Keychain for the AnyRouter key, `UserDefaults` (through `AppSettings`) for settings. |
| D11 | `Config/Base.xcconfig` is committed, `Config/Local.xcconfig` (Team ID) is gitignored, CI secrets sign. No personal values in git. |
| D12 | UI-facing service protocols live in `Features/Services/`: `AccountService` (adapter over `AnyRouterAuth`) and `ModelHubService` (adapter `LocalModelHub` over `CatalogService` and `ModelDownloadManager`). The UI imports engine types only inside the adapters. |
| D13 | Markdown uses `swift-markdown-ui` (MarkdownUI 2.4.x), themed to our colors. |
| D14 | No custom llama.cpp fork. GGUF features that need more than `libllama` (speculative decoding, TurboQuant KV) wait for an xcframework that builds `common/`. A fork is considered only if a measured on-device need remains after that. |
| D15 | UI boundary: native SwiftUI containers and behavior (split view, sheets with detents, List, Form, toolbars, Liquid Glass on the control layer, Dynamic Type, hardware keyboard) skinned with the reference tokens (colors, radii 10/14/24, spacing, markdown look). Content surfaces stay flat; glass is for navigation and controls only. Type uses text styles, never fixed sizes. |
| D16 | Chat stays one `ChatEngine`. Images, video frames and audio ride on `ChatMessage` attachments and parts. Image generation, speech to text and text to speech are separate protocols behind the same registry, so `ChatDelta` stays text-shaped. |
| D17 | Voice is two seams, `SpeechToText` and `TextToSpeech`. The System engine (`SpeechTranscriber`, `AVSpeechSynthesizer`) is always there. Downloaded engines (WhisperKit STT, TTSKit Qwen3-TTS) run only when installed, selected and the language is on their list; any other language uses the System engine. Moonshine stays Later. |
| D18 | llama.cpp is pinned to tag b12811 through `Packages/LlamaBinary`: a binaryTarget on our own xcframework (release `llama-b12811` of this repo, built by `llama-xcframework.yml`, iOS device and Simulator slices, Metal, `libllama` and `libmtmd`). Upstream ships device slices only, and CI runs on the Simulator. The looped-core 26B files need b12611 or later. To move the pin, run the workflow with a new tag and paste its URL and checksum. |
| D19 | iPhone keeps a wide sidebar drawer (82% of the screen, cap 360 pt) that the chat slides away from, with drag and edge swipe. Operator request; it deviates from the system split view on iPhone only. |
| D20 | Settings is a sheet with a `NavigationStack` and grouped list. Pages plug in through `SettingsDestination`: add a case, title and icon, a branch in `SettingsDestinationView`, and the page as its own file under `Features/Settings/Pages/`. |
| D21 | iPad uses `NavigationSplitView` with automatic column visibility. A compact-width iPad window takes the iPhone drawer path. Chat column, empty state and composer share `readableWidth()` (720 pt cap). The model picker is a popover on iPad and a sheet on iPhone. Settings and small sheets use `.presentationSizing(.form)`. |
| D22 | The Mac app is the iOS app "Designed for iPad", not Mac Catalyst. `llama.xcframework` has only iOS slices, and Catalyst would cut local models behind `#if`. Settings stays the Cmd-comma sheet. |
| D23 | One row above the composer: capsule glass chips (at most 4 presets, then a More menu with all presets and "Edit Presets"). `ComposerSuggestionLogic` is the only place that decides what shows. On an empty chat the starters are two-line glass cards (operator request; do not reopen). Copy and paste offers stay one-line chips. |
| D24 | Tools reach every model source through one registry (`ToolRegistry.makeHost`), one host (`AgentToolHost`) and one run path (`ToolRunScope`). `LocalToolEngine` gives llama.cpp and MLX a tool loop in the family's own format (Qwen, Llama 3, Gemma), at most 4 rounds. It is off until Settings > Integrations > "Tools on this device's models" is on. Apple and local models get 4 tools (clock, calculator, search, page reader first). |
| D25 | An assistant turn is a list of `ReplyPart`s (reasoning, tool steps, subagent, text, file, image, compaction marker), one view per kind. See Reply parts. |
| D27 | The conversation uses one `TraceRow` (symbol, one line, status, chevron) for reasoning, the tool chain, subagents and compaction. Failed and denied calls stay visible, approvals wait inline with Allow and Deny, a sent question settles at the top and the reply grows below it. See Reply parts. |
| D28 | One app agent for every model source (design in `docs/research/agent-design.md`): memory, one `PromptAssembler` with a token budget per engine, a resumable run state machine, one app loop (`AgentLoop`, Apple keeps its framework loop), bundled and user skills, subagents (unit S1, built), and the live eval set (unit L1, open). Defaults until the operator says otherwise: on-device memories do not reach cloud models unless the user turns that on; the agent saves memories without asking, with a "Memory updated" row and Undo; recall is lexical first, with on-device embeddings only for strong meaning-only hits. |
| D29 | Decisions, Paste and Extract are native apps. Each app and its agent tool share one service. See Apps. |
| D30 | Chat titles: the first reply asks for a 2 to 6 word title, on Apple on-device when ready, else the chat's own model, never a cloud model for a device chat. A user-set title is never replaced. |
| D31 | A failed reply stays in the chat with its failure stored on it (`MessageRecord.failureData`, one of twelve `ReplyFailure` kinds plus the raw text). It shows one plain sentence on a failed `TraceRow`, the raw text with Copy, and one action (Retry, Sign in, Choose another model, Shorten chat, Open Local Models). `ReplyFailureLogic` classifies engine errors once. The composer banner is only for what happens before a send. |
| D32 | The chat's message list is a `VStack`, not a `LazyVStack` (c3e4ac4). The lazy stack placed rows it had not laid out at estimated heights: on a short chat the estimates never settled, so after a swipe the main thread laid the list out without end (perf 46116623560: a core busy 30 s with no query), and on a long chat `scrollTo("bottom")` landed short of the end (bisect 46129022686, all three devices). Cost, Simulator Release, 200 messages (perf 46127733286): launch to responsive 8.6 s -> 12.5 s. M2 now lays out every row, so M2 numbers from before c3e4ac4 do not compare with later ones. If long chats need laziness back, `List` is the next candidate, judged by ShortChatTests and ScrollEndTests. | A hang and a broken jump arrow cost more than a slower open of very long chats. 2026-11-28, lane A. |

MiniCPM 5 stays out of `models.json`. The 1B Q4_K_M loaded on b12811 but answered "2" to "What is 2+2?" (model-smoke 46135283474). The 2B Q4_K_M passed (46133774784: answer "4", load + first token 93.89 s, 0.9 tok/s on the Simulator CPU, 1.5 GB) and waits in `dev-models.json` for the manager's call. No more smoke runs on either until a new GGUF or llama.cpp version.

## Contract (Core/)

Change it only by a reviewed change to `Core/`; do not fork the types. The base shape:

```swift
enum ModelSource: String, Codable, Sendable { case apple, gguf, mlx, anyrouter }

struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
  var id: String            // "apple/foundation", "gguf/<hf-repo>/<file>", "mlx/<hf-repo>", "anyrouter/<provider/model>"
  var source: ModelSource
  var displayName: String
  var contextLength: Int?
  var capabilities: Set<String>   // "chat", "vision", "tools", ...
  var sizeBytes: Int64?           // local models
  var isInstalled: Bool           // remote and apple: true when usable
}

struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
  enum Role: String, Codable, Sendable { case system, user, assistant }
  var id: UUID
  var role: Role
  var content: String
  var createdAt: Date
}

struct GenerationParams: Codable, Sendable {
  var temperature: Double = 0.7
  var topP: Double = 0.95
  var maxTokens: Int? = nil
  var systemPrompt: String? = nil
}

enum ChatDelta: Sendable {
  case text(String)                         // append-only suffix
  case usage(prompt: Int, completion: Int)
  case done(finishReason: String?)
}

protocol ChatEngine: Sendable {
  var source: ModelSource { get }
  func availableModels() async throws -> [ModelDescriptor]
  func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
    -> AsyncThrowingStream<ChatDelta, Error>
}

/// One registry the UI talks to. It never branches on source.
@MainActor @Observable final class EngineRegistry {
  func register(_ engine: any ChatEngine)
  func allModels() async -> [ModelDescriptor]
  func engine(for model: ModelDescriptor) -> any ChatEngine
}
```

Added since: `ChatDelta.toolCall` and `.toolResult`, a `stream(...tools:)` overload with a plain-text default, and the tool types `ToolSpec`, `ToolCall`, `ToolResult`, `ToolStep`, `ToolHost` (T3). `ChatMessage` is unchanged on purpose: an engine runs its own tool steps. New Core fields are `Codable` with defaults so stored data still decodes.

## Repo layout

```
project.yml      XcodeGen spec          Design/            tokens, ListRow, glass primitives
App/             @main, AppState, DI    Features/          Chat, Threads, ModelPicker, Hub, Settings, Onboarding,
Core/            contract, registry,                       Decisions, Paste, Extract, Memory, Skills, Voice, ...
                 SwiftData records      Engines/           Apple, AnyRouter (+Auth), Local (Catalog, GGUF, MLX),
Controls/ Share/ widget and share                          MCP, Tools, Voice
                 extensions             catalog/           models.json, dev-models.json, decision-apps.json
Tests/ UITests/  unit and UI tests      formal/            TLA+ model of the local model lifecycle
scripts/         source-check, coverage, catalog, ux-score
.github/workflows/  ci, screenshots, verify-ui, perf, model-smoke, llama-xcframework, device-ipa, testflight, ...
```

## What the app does today

**Models and engines.** Apple Foundation Models, GGUF through `GGUFEngine` (b12811, Jinja templates for models llama.cpp cannot apply, Gemma 4 and Inkling formatters) and MLX through `mlx-swift-lm` (device only; the Simulator has no Metal GPU family). AnyRouter models come from `GET /api/v1/models` and stream over SSE with `include_usage`; `ModelKind` (chat, embedding, rerank, decision) is parsed at the engine boundary and the chat picker lists chat only. Local catalog: `catalog/models.json` is fetched with an ETag and bundled as the offline fallback, `dev-models.json` is behind a Settings switch, user HF repos and HF search are supported, CI checks every entry against Hugging Face. `FitPlanner` (weights, KV cache and 1 GB overhead against the process limit, mixture-of-experts from mmap, device classes of 4 to 16 GB) drives fit badges and "Recommended for this iPhone". Models unload on a memory warning and after 5 minutes in the background. The 26B looped-core Inkling 2 Mini 1-bit build runs at about 0.3 tok/s and is badged "Experimental · slow".

**Chat.** Threads with pin, rename, delete and full-text search (`ThreadSearchScreen`), SwiftData-backed. Markdown in stable blocks with a streaming tail, copy, regenerate, stop, select text, jump to latest, scroll anchor on send. The reply footer is one quiet row (Copy, Regenerate, "Haiku 4.5 · $0.0012 · 42 tok/s", source icons); tapping it opens the reply details sheet. Text size (-2 to +3 steps) and font (System, Serif, Rounded) are settings. Per-thread tools, custom instructions and thinking flag. "Start a new chat after" delay, resume after a kill, a cold launch applies it. Offline mode skips cloud models and web tools. A context meter and "Compact conversation" sit in the More menu; compaction runs at 80% of the window.

### Reply parts

Decisions D25 and D27. `ReplyParts.make` builds the list from a message and `isStreaming`; one view per part: `ReasoningRow` ("Thinking…", "Thought for Ns"; local models go through `ReasoningSplitter`, SSE through `reasoning_content`), `ToolChainView` (folds to a sentence from `ToolChain.summary`), `MarkdownReply`, `AttachmentCard` and a zoomable image viewer, `SubagentCard` (unit 5: rendering and data from `ToolStep.children`; the engine side shipped as D28 S1), `CompactionDivider`. `TraceRow` statuses: running, done, failed, denied, awaitingApproval, cancelled. Done calls fold once the answer starts; failed, denied and cancelled calls stay. The approval card is inline. Not doing: a second renderer per part, parts as their own table, markdown images from the web (privacy).

### Tools, apps and the rest

**Tools and agent (D24, D28).** Built-in tools carry a side-effect class (`read`, `sensitiveRead`, `write`, `external`) that decides approval; writes and external calls ask every time, with no "always allow" (LA1). Tools: clock, calculator, `web_search` (Exa without an account, AnyRouter search when signed in), `fetch_url`, `read_attachment`, `ocr_image` (LA3), `memory` and `search_chats` (cloud), `decide`, `delegate_task` (cloud), `propose_skill`, `read_skill`, `notes`. Data-out rules: an address leaves without asking only when its host is in the user's own messages of this chat. Local models without a tool loop get `WebGrounding` (a search before the send, T15). `AgentLoop` saves a run at each step (`AgentRunRecord`); a killed app shows an interrupted reply with Retry, and a pending approval comes back after a relaunch. Memory: `MemoryRecord`, Settings > Memory, a capped profile frozen per thread, lexical recall with a relevance floor (share above 0.27 of the question's content words) plus on-device NaturalLanguage embeddings for strong meaning-only hits, "Used N memories" in the footer. Skills: bundled, the user's AnyRouter hub skills (`GET /api/v1/hubs/sync`) and SKILL.md URL imports (https, 64 KB); skill text is untrusted and grants no tools. Subagents run on cloud models only: read tools, at most 4 requests and 30,000 tokens, one summary back.

**Welcome.** First launch shows the logo, one line, a primary "Log in to AnyRouter" button (web sheet) and a plain "Use local models only" button. Skip goes to chat on Apple Intelligence, else to the one-model local download step.

**MCP.** `Engines/MCP/` is a small client (initialize, tools/list, tools/call, session id, JSON and SSE bodies; answers capped at 4 MB; bodies and the AnyRouter SSE stream are read in chunks through `forEachChunk`). Signing in connects `https://anyrouter.dev/api/v1/mcp` with the same Keychain token (31 tools, 26 from Firecrawl) and signing out disconnects it. Settings > Integrations holds per-tool switches, tool sources (`ToolSourceCatalog`), and custom servers (URL plus optional bearer token in Keychain). Only read-only tools start on; a custom server's read-only hint does not waive approval. The @ list in the composer shows plugins and the newest files of the chat.

**Apps (D29).** `DecisionsService` runs `POST /api/v1/decisions` for the Decisions screen, Paste and the `decide` tool: six bundled apps from `catalog/decision-apps.json`, Yes/No, Choice and Score builders (Score starts at 10 levels), photos (PNG, JPEG, WebP; at most 4; re-encoded on device, location metadata dropped), a live camera, samples, Recent runs. Paste: `PasteLogic.detect` finds JSON, JWT, cron, stack trace and color on device; only plain text goes to a decision model. Extract: photo, PDF or document camera, on-device text (`ImageTextReading`), presets (receipt, bill, invoice, email, custom), any chat model, each field with a quote located in the source; `AnyRouterOCRReader` (`POST /api/v1/ocr/extract`, 5 MiB cap) is an opt-in switch. Each app picks its model in `ModelPickerSheet` with a `ModelRequirement`. Entry: sidebar Apps section and composer "Decide about this" and "Extract fields". A sidebar row, a model pill and bottom action bars follow D15.

**Voice (D17).** Dictation (mic button, live text, language badge, permission pre-prompt) and spoken replies (sentence streaming, stop on new input). Settings > Local Models > Voice lists STT and TTS engines with Get, Delete, default and Test. WhisperKit STT (tiny to large-v3 turbo compressed) and TTSKit Qwen3-TTS 0.6B are catalog entries sized by `VoiceFit` (resident memory at most half the chat memory budget). Voice Mode cover: with no speech model installed, the voice button offers a download that runs in the background (`VoiceHub.voiceDownload`); Not Now falls back to the System engine. TTSKit has no Vietnamese, so Vietnamese uses the System voice.

**Local inference and multimodal.** Photos reach llama.cpp models through `mtmd` and a catalog `vision` field (`mmprojFile`, `imageSide`, `optional`); the projector counts in the fit check, and a text-only model gets a note naming a vision model. Device engines get each photo's on-device text recognition in the message. Camera, Photos and PDF attachments work with Quick Look. Device tool calling works only for Qwen, Llama 3 and Gemma families, behind the switch.

**Settings.** Root list fits one iPhone screen: account card; Models (Local Models with Advanced > Catalog Sources, AnyRouter Models); Chat (Responses with Advanced, Presets, Integrations, Memory, Skills, Chat Behavior); App (Shortcuts & Controls, Theme, Privacy, About). Delete All Conversations is in Privacy. Row icons come from `SettingsIcon` and `ARPalette` (one mono tint, a tile color per page). `scripts/source-check.sh` fails on `Color(red:`, `Color(hex`, `UIColor(red:` and `.foregroundColor(` in Features/, and on duplicate file names or types named like Swift Testing types. AnyRouter Models: search, sort (Top this week from `/analytics/top-models`, Newest, Cheapest, Free, Name), filters, Star and Hide, Set as Default. Every model owner has a logo (`Design/model-brands.json`).

**Entry points.** App Intents and App Shortcuts (Ask AnyRouter, Reply to this, Fix my English, headless Run preset, Summarize, Translate, Ask with model, New chat, Start voice), Control Center and Lock Screen controls (`Controls/`), a Share extension through the App Group `group.oneni.anyr.app` (it degrades with a message where App Groups are unavailable, such as a free-Apple-ID sideload), read text from a photo, Reply helper, clipboard offers.

**Diagnostics and verification.** `Telemetry` boundary in Core, MetricKit store (newest 20), optional Sentry behind `SENTRY_DSN` with a Privacy opt-out, Settings > Diagnostics (memory and stall rows, main-thread watchdog, failures such as "No cloud models" with Retry). A TLA+ model of the model lifecycle (`formal/`) is checked by TLC in `verify-formal.yml`.

**CI.** `ci.yml` builds and tests on the iOS Simulator and gates 100% lines on Core and on logic, stores, view models, the AnyRouter engine, the catalog and downloads (`scripts/coverage-gate.sh`). Other workflows: screenshots (iPhone and iPad, light and dark), verify-ui (accessibility audit journeys), perf, model-smoke (real GGUF through `GGUFEngine`, installer, downloads, Apple availability), ipad-ui, mac (unsigned Designed-for-iPad launch screenshot), device-ipa (unsigned IPA after CI, docs/sideload.md), testflight, llama-xcframework, gitleaks (also bans the reference names), catalog. An iOS-only change needs no local build.

## Native UX & performance

Rules (D15): 44 pt hit areas, text styles only, no glass on glass, semantic colors that pass contrast, haptics never per token, Reduce Motion respected. Perf metrics M1 to M5 come from the Simulator on a shared runner and only rank changes; a change counts only when it moves the mean by more than twice the spread across 3 runs of 5 iterations.

| ID | Metric | How CI measures it | Current reading |
|---|---|---|---|
| M1 | Cold launch to responsive | `XCTApplicationLaunchMetric`, signposts split container, engines, auth, hub | About 4 to 8 s, mostly Simulator and XCUITest; our signposts add up to about 0.3 s |
| M2 | Chat scroll | `XCTCPUMetric`, 8 swipes on a 200-message thread | About 10 s, dominated by the accessibility runtime in the test, not by the app; device target: hitch ratio under 5 ms/s |
| M3 | Streaming cost | 1,000 tokens at 50 tok/s, CPU and memory minus an idle control | One core busy for the whole reply; peak 89 MB. This is what U3 targets |
| M4 | Picker open | 500 models, tap to first row | 8 s more CPU than a 6-model control (U9) |
| M5 | First usable model | cloud list delayed 5 s, `models.firstUsable` | 2.4 s; target under 2 s whatever the delay |

## Voice roadmap

Open: Moonshine streaming STT for Vietnamese and English once the language is known, VieNeu-TTS through llama.cpp, Moonshine TTS voices (V6b, V7 below). A Vietnamese voice licence could not be verified. Refused: MMS-TTS (non-commercial); Piper `vi_VN` (its phonemizer is GPL-3.0).

### On-device eval list (the CI Simulator has no microphone)

- STT: word error and real-time factor on fixed 30 s English and Vietnamese clips for the System engine and Whisper base, small and large-v3 turbo compressed, per device class, with thermal state.
- Language detection: 20 short clips (10 English, 10 Vietnamese, 5 mixed) through both detectors; wrong picks and seconds until the badge settles.
- TTS: time to first audio and real-time factor for one English and one Vietnamese sentence per engine; the quality tier (`default`, `enhanced`, `premium`) of the best Vietnamese system voice on a clean install.
- Memory: peak footprint with a Whisper model loaded next to a 3B chat model on a 6 GB device. `VoiceFit` uses 2.2 times the download as an estimate until this runs.

## Open work

Ids are stable. Delete a line when the task is done.

**Release and CI**
- F1 Device smoke on iPhone and iPad: sign-in, Apple chat, GGUF and MLX download and chat; background downloads stay device-only.
- E1 TestFlight upload path is untested until the secrets exist (Q1, Q2).
- F7 Mac: XCUITest cannot drive "Designed for iPad" on a Mac; screenshots only.
- F8b Compare screenshots with the reference mobile screenshots. F8c UX scorecard (`docs/ux-rubric.md`, `scripts/ux-score.py`, `ux-score.yml`) stays a work in progress.
- F19 Part 2: XCUITest flows for every screen in a separate ui-tests job on iPhone and iPad.
- F20 Adopt the first-party mobile client and universal-link sign-in callback when the server side ships.
- F21 UI E2E against prod AnyRouter, gated on `ANYROUTER_E2E_API_KEY` (skipped when absent, never on fork PRs).
- F23 CI speed and cost: one build for many tests, compilation caching, path-aware jobs, Xcode-free checks on Linux.
- F24 UI test matrix: one iPhone per push, nightly device matrix, Dynamic Type and landscape.

**Models and engines**
- C10 Photos for local models: run `testNamesTheColorOfAPhoto` in model-smoke and on a device.
- F3 GGUF KV-cache reuse between turns.
- F5 Bundle Inter (OFL); syntax highlighting in code blocks.
- F17 Engines read `ThreadRecord.thinkingEnabled` (chat template switch for Qwen3 and Gemma 4, AnyRouter `reasoning` option).
- S2 Core inference types with defaults and `validated(for:)`: `FlashAttention`, `KVCacheScheme`, `SpeculativeMode`, `ContextPolicy`, `InferenceSettings`.
- S3 Catalog: Ministral 3 3B Instruct, Phi-4-mini-instruct, Qwen3.5 4B, with golden prompt tests per family.
- S4 Benchmark runner in Core, Settings > Developer screen, JSON export (same prompts, greedy, cold and warm, 5 runs, thermal state).
- S5 GGUF flash attention and KV type (q8_0, q4_0) from `InferenceSettings`; quantized V needs flash attention on.
- S6 `ReasoningTracker` state machine and `.strip` history policy with tests for tags split across chunks.
- S7 `ContextPolicy`: grow `n_ctx` or the MLX window up to a ceiling, else trim or fail, with a one-line notice; replaces the fixed MLX `maxKVSize`.
- S8 MLX MTP drafters (Gemma 4, Qwen 3.5) as catalog `companions`, token-parity check, "Speculative: on/off (reason)" row. S9 MLX TurboQuant KV behind an Experimental row, off by default, after S7.
- Later: GGUF speculative decoding (MTP, DFlash) and TurboQuant KV need an xcframework with `common/` (D14); EAGLE-3 drafters are too large for phones.

**Agent and tools**
- L1 Live suite in `model-smoke.yml` and the on-device list: LA11 tool-calling prompts, memory recall on a device with Apple's contextual embeddings, the real Apple extraction call.
- LA11 Tool-calling eval set (about 20 prompts per engine); no engine gets tools on by default without a pass.
- LA2 `DevicePermission` broker and Settings > Integrations > "On this device" with per-tool switches; sensitive tools off by default.
- LA4 `calendar_search` and reminders search (EventKit, 20 results). LA5 `reminder_create` and event creation behind a confirmation card. LA6 `contacts_lookup`. LA7 `place_search` (MapKit) and `weather` (WeatherKit capability from the operator). LA8 `translate_text`.
- LA9 Taint rule in `ExfiltrationGuard` (after a sensitive read, outbound tools ask for the rest of the turn), spotlighting of tool output, one-time notice when a sensitive result goes to a cloud model.
- LA10 Tool selector by group; `AppleDynamicTool.maxTools` 8 to 4; result budget from `tokenCount(for:)` on 26.4 and later. The 4-tool cap and its order are in.
- LA12 `AskAnyRouterIntent` returning an answer to Shortcuts (read tools only). LA13 `run_shortcut` for user-registered shortcuts, asks every time. LA14 Tool calling for MLX through the `mlx-swift-lm` processor, GGUF once `common/` exists. LA15 Later: Siri AI tool intent (iOS 27.3, internal TestFlight only). LA16 Later: Core Spotlight index of chat titles, off by default.
- T7 Local GGUF and MLX tool calling beyond Qwen, Llama 3 and Gemma: chat-template tool rendering and parsing per family. Until then `WebGrounding` covers search.
- Open from the loop: `decide` runs without asking and has no switch; Deny on resume and local resume are untested; "Remember this" on the user's own bubble; editing a stored skill.

**Multimodal (later)**
- R3 MLX vision through `MLXVLM` (device only). R4 `FrameSampler` for video (at most 1 frame per second, 8 frames, long edge 512 px). R6 Audio input through `mtmd` with Gemma 4 E2B. R7 ImagePlayground sheet behind an availability check. R8 `ImageGenerationEngine` with a Core ML Stable Diffusion engine and an Images screen. Not planned: video and music generation on phones.

**Apps**
- AP1b Each decision app as a Shortcuts action. AP6 Screenshots of Decisions, Paste and Extract, light and dark.

**UX and performance**
- U3 Streaming path: flush streamed text at most 20 to 30 Hz (a 20 Hz `TextCoalescer` exists), write the record on finish and every 2 s as a checkpoint, stop reading content in the list body (M3).
- U4 Row identity: an equatable `MessageRowModel`, actions through the environment, one cached theme, an ordered array kept in the view model.
- U9 Picker and Hub lists: lazy containers, sections cached in `ModelStore`, a 150 ms search debounce, per-card progress observation (M4).
- U14 Accessibility: zero audit issues on the main screens. U25 Dynamic Type audit at the largest accessibility size on home, chat, picker and Settings.
- U15 Thread search with a predicate fetch and debounce, once a measurement shows a need. U17 Deep links and an opt-in Spotlight index. U18 Chunked SSE read, only if M3 on the real SSE path shows it.
- Accessibility audit, still open: preset chips clip at AccessibilityXL; picker rows truncate names at AccessibilityXL; the response-details row clips. Re-audit the rest with `gh workflow run verify-ui.yml`.
- Review findings left: `fatalError` when the store fails to open and no versioned schema exists; `Records.swift` decodes JSON on every access; the picker refreshes only on sign-in; `device-ipa.yml` builds a second device IPA after every main CI run (macOS minutes cost 10x).

**Voice**
- V6b Later: Moonshine TTS voices for Vietnamese. V7 Later: Moonshine streaming STT; VieNeu-TTS through llama.cpp.

## Open questions (operator)

- Q1 Add GitHub secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (API key role App Manager).
- Q2 Create the app record in App Store Connect (bundle id `oneni.anyr.app`, name AnyRouter).
- Q6 Verify-later sign-up is a Clerk dashboard setting, not code. Until it is off, new users are verified before the app gets its key and the Settings "Verify your email" row never shows. The server must also return `email_verified` from `/me` (duyet/anyrouter#8468). The app treats a missing field as verified.
- Q7 "No cloud models" on a signed-in device: the public catalog decodes fine, so the cause is on the signed-in path and is not proven without a key. The reason and Retry now show and Diagnostics keeps it. If it happens again, read the Diagnostics line.
- Q8 The reply details sheet shows only what a message stores. Not stored: tool call duration, agent rounds, granted approvals, reasoning tokens, cost breakdown, context used, prompt sections with token counts, per-reply compaction events, finish reason. Which should the loop and engines record (one optional, decode-safe field each)?
- Q9 Decisions photos: confirm the server returns 400 `invalid_images` when a backend cannot read images (the app maps it to "This model can't read photos"), and what an empty `state` with photos does.
- Q10 Model picker "Not available" (01be7d1): the "Get credits" link `https://anyrouter.dev/dashboard/credits` is a guess; confirm the URL. The "Hide models that need your key" filter no longer changes the list (models that need a key always sit under Not available): remove it or give it another job?
- Q11 "Scroll to bottom not working" (operator) also names "finishing a reply doesn't land at the end". D27 says a reply that ends leaves the reader where they are (`ScrollFollow.settle(.streamEnded) -> .stay`), with the question settled at the top, so a reply longer than the screen ends below the fold by design. Which wins: keep D27, or scroll to the end when a reply finishes?

## Out of scope

Projects, RAG and vector databases, a local API server, a system monitor, remote LAN, cloud sync, a macOS target other than Designed for iPad, video and music generation. Keep a "Coming soon" slot only where the reference mobile layout shows one; do not delete a surface.
