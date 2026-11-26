# PLAN.md — AnyRouter for iPhone and iPad

Owner: operator. Manager: main Claude session. Workers: lane agents (see AGENTS.md).
Last updated: 2026-11-26.

## Goal

A native SwiftUI app **AnyRouter** for iPhone and iPad that follows a reference mobile chat UI and UX
(own AnyRouter branding) and chats with:

1. **Apple Foundation Models**, on device
2. **Local Hugging Face models**, GGUF (llama.cpp) and MLX, from a configurable catalog
3. **AnyRouter models**, after **Sign in with AnyRouter** (OAuth + PKCE)

**Milestone 1:** a TestFlight internal build installed on the operator's own iPhone and iPad.

## Decisions (from the operator interview, 2026-11-26)

| # | Decision | Why |
|---|---|---|
| D1 | Native SwiftUI clone, not the Tauri fork | Operator choice. Native FoundationModels/MLX, small app. The look follows the reference design, written natively. |
| D2 | Public open-source repo `github.com/AnyRouterHQ/AnyRouterApp`, Apache-2.0 | Operator choice. Public also gives free macOS CI minutes. |
| D3 | Both GGUF (llama.cpp) and MLX engines behind one `ChatEngine` protocol | Operator choice |
| D4 | Milestone 1 = TestFlight internal build | Operator choice. Automatic signing with an App Store Connect API key; needs 4 secrets and an app record (see Open questions). |
| D5 | iOS/iPadOS 26.0 minimum, universal app (iPhone + iPad) | FoundationModels needs 26. One target. |
| D6 | Bundle id `dev.anyrouter.app`, display name `AnyRouter` | Matches the `dev.anyrouter.*` family. |
| D7 | XcodeGen `project.yml`, no committed `.xcodeproj` | Parallel lanes add files without pbxproj conflicts. |
| D8 | CI on GitHub Actions macOS runners is the only build | Operator Mac has no Xcode and a no-local-build rule. |
| D9 | OAuth: dynamic client registration (`/api/v1/mcp/oauth/register`) + PKCE + loopback `127.0.0.1` callback via `ASWebAuthenticationSession` | Pattern proven on device in an earlier AnyRouter iOS prototype; the server rejects custom URL schemes. |
| D11 | Config: `Config/Base.xcconfig` (committed) + `Config/Local.xcconfig` (gitignored) for Team ID; CI secrets for signing | Open source: no personal values in git. |
| D12 | UI-facing service protocols live in `Features/Services/`: `AccountService` (adapter `AnyRouterAccountAdapter` wraps lane B's `AnyRouterAuth`) and `ModelHubService` (adapter `LocalModelHub` wraps lane C's `CatalogService` and `ModelDownloadManager`). Lane D owns the adapters, so B and C change nothing. `AppState` holds both. | UI never imports engine types except inside the adapters. |
| D13 | Markdown rendering uses `gonzalezreal/swift-markdown-ui` (MarkdownUI 2.4.x) | Maintained, SwiftUI-native, themeable to our colors. |
| D20 | Settings is a sheet with a native `NavigationStack` and grouped list. Pages plug in via `SettingsDestination` (`Features/Settings/SettingsDestination.swift`): add a case, its title and icon, put it in a `Group`, add a branch in `SettingsDestinationView`, and write the page as its own file under `Features/Settings/Pages/`. Presets and MCP lanes replace `PresetsSettingsView` and `IntegrationsSettingsView` and leave the list alone. | Parallel lanes add pages without touching the list layout. |
| D10 | Persistence: SwiftData for threads/messages; Keychain for the AnyRouter key; `UserDefaults` for settings | Simplest native stack. |
| D14 | No custom llama.cpp fork in v1.x. GGUF features that need more than `libllama` (speculative decoding, TurboQuant KV) wait for F4: our own xcframework built from an official tag. A fork is considered only if a measured on-device need remains after F4. | The official tags already carry MTP, DFlash and EAGLE-3 in `common/`. Forks add upkeep and licence review, and the app ships weights, not new engines. |
| D18 | llama.cpp is pinned to tag b12603 through the local package `Packages/LlamaBinary`: a binaryTarget (URL + checksum) on our own xcframework, release `llama-b12603` of this repo, built by `.github/workflows/llama-xcframework.yml` (iOS device and Simulator slices, Metal, `libllama` and `libmtmd`) | Upstream releases ship device slices only since b10488, and CI runs on the Simulator. b12603 is the first tag that loads the looped-core 26B mixture-of-experts model, and it covers Gemma 4, Qwen 3.5, LFM2 and SmolLM3. The API change that matters here: `use_mmap` became `load_mode`. To move the pin, run the workflow with a new tag and paste its URL and checksum. |
| D19 | iPhone keeps a wide sidebar drawer (82% of the screen, cap 360pt) that the chat slides away from, with interactive drag and edge swipe. This is an operator request and deviates from U10a for iPhone only. iPad uses `NavigationSplitView`. Settings and its pages already follow U10b (sheet, `NavigationStack`, grouped list). | The operator wants the drawer look of the reference screenshots; the system compact split view cannot slide the chat aside. |
| D21 | iPad uses `NavigationSplitView` with automatic column visibility: the sidebar sits beside the chat in landscape, floats over it in portrait (iPad mini included) and closes after a pick. A compact-width iPad window (Slide Over, one-third Split View) takes the iPhone drawer path. The chat column, empty state and composer share `readableWidth()` (720pt cap, margins included). The model picker is a popover under the model title on iPad and the usual sheet on iPhone. Settings and small sheets are `.presentationSizing(.form)`, Browse models a page. | The system gives Stage Manager resizing, the toolbar toggle and pointer behavior for free; a toggle made in one orientation is not carried into the other. |
| D22 | The Mac app is the iOS app "Designed for iPad" (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`), not Mac Catalyst. | `llama.xcframework` has only `ios-arm64` and the iOS Simulator slice (llama-xcframework.yml builds `ios-sim ios-device`), so a Catalyst or macOS link fails; `mlx-swift-lm` lists macOS and iOS but not Mac Catalyst. Designed for iPad runs the iOS device slices on Apple silicon, so local GGUF and MLX models keep working with no source change. Catalyst would also mean cutting local models behind `#if`. No Settings scene: the SwiftUI `Settings` scene is macOS only, so Settings stays the Cmd-comma sheet. |
| D15 | UI boundary: native SwiftUI containers and behaviors skinned with the reference design's tokens (colors, radii, spacing, type scale). Per-screen deviations are listed in § Native UX & performance. | The reference is a web app; native containers give edge-swipe back, restoration, Liquid Glass, Dynamic Type, keyboard and pointer support that custom views cannot. |
| D16 | Chat stays one `ChatEngine`; images, video frames and audio ride on `ChatMessage.parts`. Image generation, speech-to-text and text-to-speech are separate protocols (`ImageGenerationEngine`, `SpeechRecognizer`, `SpeechSynthesizer`) behind the same registry. | Their input and output are progress, previews and audio streams, not text deltas. Overloading `ChatDelta` would make every chat engine handle them. |
| D17 | Speech uses system frameworks first (`SpeechTranscriber`, `AVSpeechSynthesizer`). Open speech models are opt-in extras later. | No download, no model upkeep, no app-size cost. |
| D18 | Voice is two seams, `SpeechToText` and `TextToSpeech`, each with a System engine that is always there and downloaded engines the user picks in Settings. A downloaded engine runs only when installed and selected, and only for languages it lists; any other language uses the System engine. STT downloads: WhisperKit (MIT, Core ML). TTS downloads: TTSKit Qwen3-TTS (Apache-2.0 weights, Core ML); Moonshine Voice (MIT, ONNX) stays Later. | The user wants local voice models, but Vietnamese is the language the open models cover worst, so the fallback is decided per language, not per app. See the Voice roadmap. |

## Out of scope for v1

Reference-design features not ported in v1: agents/skills, MCP connectors, projects, RAG/vector DB, audio, images, videos,
local API server, system monitor, remote LAN, cloud sync, macOS target. Keep the UI slots only where the reference
mobile layout shows them and mark them "Coming soon" (do not delete the surface).

## Contract (Core/, owned by lane A; change only by PR)

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

Cancellation: dropping the stream's consumer `Task` must stop generation (use `continuation.onTermination`).

## Repo layout

```
project.yml                      lane A
App/                             lane A   @main, AppState, DI, Info.plist, assets, entitlements
Core/                            lane A   contract above, EngineRegistry, SwiftData models (Thread, Message)
Design/                          lane D   color and layout tokens, typography, components
Features/Chat/ Threads/ ModelPicker/ Hub/ Settings/ Onboarding/   lane D
Engines/Apple/                   lane B   FoundationModels engine
Engines/AnyRouter/               lane B   OAuth, Keychain, models list, SSE chat stream
Engines/Local/Catalog/           lane C   HF catalog (configurable), search, downloads
Engines/Local/GGUF/              lane C   llama.cpp engine
Engines/Local/MLX/               lane C   MLX engine
Tests/                           each lane under Tests/<Lane folder>/
.github/workflows/               lane A (lane E adds signing)
```

## Lanes and tasks

Run at most 3 lanes at once. Lane A merges first (B and C may start in parallel and rebase onto A).

### Lane A — scaffold, core, CI (model: sonnet-low)
- [x] A1 `project.yml`: app target `AnyRouter` (iOS 26, iPhone+iPad, `dev.anyrouter.app`), test target, SPM packages section, Release: `DEAD_CODE_STRIPPING=YES`, `SWIFT_COMPILATION_MODE=wholemodule`, `-Osize` only if it measurably shrinks the IPA (#1)
- [x] A2 `Core/` contract types + `EngineRegistry` + SwiftData `ThreadRecord`/`MessageRecord`, with unit tests (#1)
- [x] A3 `App/` shell: `@main`, root `NavigationSplitView` placeholder, AnyRouter app icon + accent from anyrouter brand (#1)
- [x] A4 CI `.github/workflows/ci.yml`: macOS runner with Xcode 26, `brew install xcodegen`, `xcodegen`, build + test on iOS Simulator, cache SPM + DerivedData, concurrency cancel. Target < 8 min warm. (#1)
- [x] A5 `THIRD_PARTY_NOTICES.md` (linked libraries), `README.md` (build steps, screenshots later) (#3)
- [x] A6 Open-source CI/CD hygiene: `gitleaks.yml` on PR + push, `dependabot.yml` (github-actions, swift), `.github/pull_request_template.md`, issue templates (bug, feature), `CONTRIBUTING.md` pointing at AGENTS.md, `SECURITY.md`; wire `Config/*.xcconfig` into `project.yml` (#3)

### Lane B — Apple + AnyRouter engines, auth (model: sonnet-medium; auth is a security path)
- [x] B1 `Engines/Apple`: `AppleFoundationEngine` (availability states, streaming snapshots → append-only deltas, instructions from system prompt) (#2)
- [x] B2 `Engines/AnyRouter/Auth`: `OAuthClient` + `KeychainStore` (lane brief gives the prototype to port); sign in, sign out, key status; client name "AnyRouter for iOS" (#2)
- [x] B3 `Engines/AnyRouter`: `GET /api/v1/models` → `ModelDescriptor`s; `POST /api/v1/chat/completions` with `stream: true` SSE parser; app attribution headers per AnyRouter docs; 401 → signed-out state (#2)
- [x] B4 Tests: PKCE challenge, SSE parsing (fixtures incl. `[DONE]`, usage chunk, error chunk), models decoding (#2)
- [x] R-decisions `ModelKind` (chat | embedding | rerank | decision) parsed at the engine boundary, chat picker lists chat only; Decisions screen (sidebar row, `POST /api/v1/decisions`, last 20 runs in SwiftData) (7d4b8a1)

### Lane C — local Hugging Face models (model: sonnet-high)
- [x] C1 `Engines/Local/Catalog`: bundled `catalog.json` (curated small models that fit phones: e.g. Qwen3 0.6B/1.7B/4B, Gemma 3 1B/4B, Llama 3.2 1B/3B, in GGUF Q4_K_M and MLX 4-bit), user-editable list of HF repos + optional remote catalog URL in Settings, HF search (`/api/models?search=&filter=gguf|mlx`), device-fit check (RAM vs size) (#7, data layer; Settings UI is D6)
- [x] C2 Downloads: background `URLSession`, resume, progress, disk usage, delete; store under Application Support, excluded from iCloud backup (#7)
- [x] C3 `Engines/Local/GGUF`: llama.cpp via official `llama.xcframework` (pinned release, SPM binaryTarget with checksum), chat template from GGUF metadata, Metal offload, streaming tokens, cancel (#10)
- [x] C4 `Engines/Local/MLX`: `mlx-swift-lm` (MLXLLM/MLXLMCommon), load from downloaded snapshot, streaming, cancel; disabled on Simulator (no Metal GPU family) with a clear message (#11)
- [x] C5 Tests: catalog decode/merge, HF search URL building, fit check, download state machine (#7, GGUF and MLX engine tests land with C3/C4)
- [x] C6 (a17003a) Two-level model browser, data and logic: catalog schema v2 with families and sizes, `status` current/deprecated with `replacedBy`, `FamilyLogic` (grouping, fit summary, recommended size per device, sorts, filters). The views are lane D (6bf4b88).
- [x] C7 (51f1f39) Fit check that matches llama.cpp: embedding tables that mmap keeps out of RAM are not counted (Gemma 4 E2B needs ~2.5 GB, not 4.4 GB), the standard-limit note, Settings > Diagnostics memory and stall rows, main-thread watchdog and hang-guard test, batched text updates, "Loading <model>" in chat, warm-load after the first frame.
- [x] C8 (9d0ae28, 82b0f2f) Jinja chat templates for GGUF models whose template llama.cpp cannot apply (needed by the 26B looped-core model). Proven by model-smoke run 45880125082: the prompt goes through the Jinja path, the answer to 2+2 is 4 and generation stops on the model's end token. On the Simulator CPU it loads in about 135 s and decodes at 0.2 tokens per second, so a device run is still needed for real speed.
- [ ] C10 Photos for local models: llama.cpp `mtmd` with the `mmproj` projector (already in our xcframework; MLX VLM is device-only and needs a new dependency). Vision shows on a size only when it has a projector and room for it, photos are scaled to the catalog's `imageSide`, the projector counts in the fit check, a text-only model gets a note naming a vision model. Open: the smoke run of `testNamesTheColorOfAPhoto` and a device run.
- [x] C9 (0a74090) Device classes (4, 6, 8, 12, 16 GB) with standard and increased memory budgets, the "Recommended for this iPhone" list from FitPlanner over them, the `mobile` tag checked by a test, `DeviceFit` deleted. A catalog edit that breaks a class fails `DeviceClassTests`.

### Lane D — UI clone of the reference mobile design (model: sonnet-medium; starts after A merges)
- [x] D1 (#8) `Design/`: color tokens (light/dark → `Color`), radius 10pt, fonts, spacing; AnyRouter brand accent
- [x] D2 (#8) Threads sidebar: new chat, search, pinned, rename, delete; compact on iPhone, split on iPad
- [x] D3 (#9) Chat screen (message list, markdown with code blocks, copy, regenerate, stop)
- [x] D4 (#12) Model picker: grouped by source, install state, sign-in prompt for AnyRouter
- [x] D5 (#12) Hub: catalog list, search, download/delete with progress, fit badge
- [x] D6 (#13) Settings: account (sign in/out), model providers, catalog sources editor, generation defaults, appearance, about + licenses
- [x] D7 (#13) Onboarding: first launch → pick Apple / download small local / sign in
- [x] D8 (#29) Default model and picker: signed-in default is the auto router (shown as "AnyRouter"), BYOK hidden but searchable, routers then providers, per-thread model with notice, model name under replies
- [x] D9 (a1b5e2c) Native model picker: sheet with Local | AnyRouter tabs, search, sort menu, Top picks (bundled top-picks.json plus the 6 hour cached usage order), two-line rows with logo, price, context and upstreams, needs-key rows with the BYOK explainer, router detail (routing-preview). ModelBrand and ModelLabel with bundled mono logos (lobe-icons, MIT), `scripts/model-name-check.sh` keeps names and logos together
- [x] D11 (afe0269) Logo for every model owner: `Design/model-brands.json` is the one brand table (ModelBrand and `scripts/logo-coverage.py` read it), 28 more lobe-icons marks via `scripts/logo-add.py`, letter monogram for owners with no public mark (`noMark` list, checked by a fixture test), 55/103 live owners have a mark (was 25)
- [x] D12 (7a6ffad) Models by weekly usage: "Top this week" is the default AnyRouter sort, fed by the public `GET /api/v1/analytics/top-models?period=this_week&limit=500` (rank, tokens, requests; cached 6 h; replaces the order-only `/models?sort=usage`). Rows: Free badge or price, context, eye/brain/wrench symbols, rank for the top 10 and weekly tokens when they fit. The info button pushes `CloudModelDetailView` (description, provider, pricing with cached input, context, max output, knowledge cutoff, upstream providers, last 7 days, links), mapped by `ModelDetailLogic` from a recorded `/models` fixture. Without a search the AnyRouter tab is short: Current (when off the list), Starred, routers, "Top this week" with the top 10, then "Show all models"; searching, sorting or filtering looks through the whole catalog.
- [x] D10 (9e75d3a) Response details under each reply: served model ("AnyRouter → X"), cost, first token, total, tok/s, tokens, request id; "Switched to X" note; setting "Show response details"

### Lane E — TestFlight (model: sonnet-low; blocked on operator secrets)
- [x] E1 (upload path untested until secrets exist) `testflight.yml`: automatic signing with the ASC API key, `xcodebuild archive` + `-exportArchive` (method `app-store-connect`, destination `upload`), unique build number, dSYMs artifact
- [x] E2 `docs/testflight.md`: app record, API key, secrets, run, internal testers, TestFlight install

## Lane G — sidebar and settings IA

- [x] G1 Settings as a drill-down sheet (Models, Chat, Appearance, About), `SettingsDestination` routing, account card with `AccountSummary` from /me, /credits and /key (926ac73)
- [x] G2 Wide sidebar drawer on iPhone (interactive drag, edge swipe), `NavigationSplitView` sidebar on iPad, bottom search and compose buttons (926ac73)
- [x] G3 (4084c6c) Settings information architecture: Models (Local Models, AnyRouter Models), then Chat (Response Customization, Presets, Integrations), Appearance, About. Local Models is one screen: System (Apple Intelligence, Advanced links to the generation settings), Featured (best size per family from `FitPlanner`, Get), Browse all models (the old browser), Not available on this device (reason per size, "Needs about 3.9 GB, this iPhone allows 3.2 GB"), Installed, Sources (Catalog Sources with a page per source), Storage with Delete All Models behind a confirmation, and the accuracy footer. "Default model" page removed: Set as Default is on every row, and Settings says when the saved default is gone and which model took over (`ModelStore.defaultNote`). `SettingsLogic`, `LocalModelsLogic`, `CatalogSourcesLogic` and UI tests `SettingsModelsTests`.
- [x] G4 (415ac71) AnyRouter Models: search, Sort (Top this week, Newest, Cheapest, Free, Name), filters, swipe to Star or Hide, Starred section that also leads the model picker, Hidden (N) page to bring models back, Set as Default in the context menu. Marks are saved in `ModelStore.cloudPrefs` (`CloudModelPrefs`).
- [x] G5 (3c35127, replaced by 2123b36) Voice in Local Models. My first version listed Kokoro, Soprano, Pocket TTS and Qwen3 TTS as "Coming soon"; the voice lane shipped real voice engines at the same time, so Local Models now has a Voice row that opens `VoiceModelsScreen` (system voices and downloadable models with size, fit and Get). The two lanes had defined a `VoiceModel` type each, which broke main; the coming-soon list was removed.
- [x] G6 (ca82945) Presets on paste: a block of 24 or more characters appearing in the composer at once shows the presets marked "Offer when pasting" above the field; tap puts the prompt before the text. Switch in the preset editor and Settings › Presets › Offer when pasting; Fix my English is on by default. Logic in `PasteOfferLogic`.
- [x] G8 (bbcd999) Delete All Conversations moved from Chat into Settings › Privacy: count in the footer, confirmation that says how many go and that it can't be undone, disabled when there are none. Theme UI test scrolls to its row.
- [x] G9 (e131009) Start a new chat after (Chat, default 1 minute): `ResumeLogic.decide` (boundary at exactly the delay, Immediately, Never, a streaming reply keeps the chat, no clock time keeps it), `lastBackgroundedAt` kept on disk so a quit and relaunch counts, no empty thread stored.
- [x] G10 (b76ddd0) Clipboard row above the composer when text was copied since the last offer: the system Paste button first, then the presets marked "Offer when pasting" (Fix my English, Translate, Summarize, Reply to this). The app only reads `changeCount` and `hasStrings`; a preset tap reads the text itself (the system's Allow Paste alert appears there, never at launch, unless the person set Paste from Other Apps to Allow). Own copies are not offered back.
- [x] G11 (e3f12c3) Live preview under Show response details: the real reply row fed with `DemoData.sampleReply()`, not tappable, one VoiceOver label.
- [x] G12 (9afeb77) Custom Instructions screen (templates Concise, Teacher, Vietnamese replies, Code reviewer; count; which models use it) and "Instructions for this chat" in the chat's more menu, saved on `ThreadRecord.instructions`, header tag "Custom instructions". Precedence: chat, then global, then none (`InstructionsLogic.effective`).
- [ ] G7 Open: Local Models › Catalog Sources has no "last refresh" line (the catalog service does not expose it); the paste offer is covered by unit tests only (the system paste prompt cannot be driven in UI tests).

## Lane H: diagnostics

- [x] H1 `Telemetry` boundary in Core/ (events, no-op, logging), MetricKit crash/hang/metric store (newest 20) with Settings, Diagnostics, optional Sentry behind `SENTRY_DSN`, Settings, Privacy opt-out, `docs/privacy.md` (9707f88)

## Lane V: formal verification

- [x] V1 TLA+ model of the local model lifecycle (`formal/`): one generation gate and one loaded model across both engines, unload vs a load in progress, delete vs a send, Stop at the gate. TLC and a conformance script run on Linux in `verify-formal.yml`; skill `.claude/skills/verify-local-model-lifecycle`. Found and fixed four ordering defects (c870204, 5ee5c22)

## Tools & integrations (MCP)

Operator request: tools and integrations through AnyRouter's MCP server. Sign-in token works against `https://anyrouter.dev/api/v1/mcp` (streamable HTTP, bearer). Core read-only tools plus Firecrawl web tools when the user connected Firecrawl; management tools are not exposed to sign-in tokens. Phases land as separate PRs.

Decision: a small focused client (`Engines/MCP/`) instead of the official MCP Swift SDK. We need only initialize, tools/list, tools/call, a session id and JSON or SSE bodies; it avoids a new package graph that we cannot build locally.

- [x] T1 `Engines/MCP/`: `MCPClient` (initialize, tools/list with paging, tools/call, session id, protocol version, one re-init on 404, JSON and SSE bodies), typed `MCPServer`, `MCPTool`, `MCPToolResult`, `JSONValue`; fixture tests with a stubbed URLSession; opt-in live test gated on `ANYROUTER_E2E_API_KEY` (#33)
- [x] T2 Settings › Integrations (`Features/Integrations/`): AnyRouter card (connected when signed in), live tool list with persisted per-tool switches, add custom server (URL + optional bearer token in Keychain), connection test with clear errors (#33)
- [x] T3 Core data shape (3e41ef6): `ToolSpec`, `ToolCall`, `ToolResult`, `ToolStep`, `ToolHost`, `ChatDelta.toolCall` / `.toolResult`, and a `stream(...tools:)` overload with a plain-text default. `ChatMessage` is unchanged on purpose: an engine runs its agent loop inside one `stream` call and reports steps as deltas; steps are kept on the assistant `MessageRecord` for display, not replayed to the model on later turns.
- [x] T4 AnyRouter engine (a9f68eb, 728056a): enabled tools sent as OpenAI `tools` (catalog tag `function-calling` maps to the `tools` capability), streamed `tool_calls` fragments joined by index, agent loop (max 8 rounds, then `tool_choice: none`), one summed usage delta, cancel-safe; `MCPToolHost` runs calls through MCP with approval for tools not marked read-only and per-tool "always allow"
- [x] T5 Chat UI (c6b1b4b): tool-call rows (expandable), approval sheet for tools not marked read-only, "Tools" toggle in the composer and menu
- [x] T6 Apple Foundation Models (019dd28): wrap enabled tools as `Tool` conformances with a dynamic `GenerationSchema` (`Tool.Arguments = GeneratedContent` works, verified in Apple docs; first 8 tools, results capped at 6000 chars for the 4k context)
- [x] T8 MCP on sign-in: signing in connects the AnyRouter server with the same Keychain token, signing out disconnects it and clears its tools at once; a custom server's read-only hint no longer waives approval; MCP answers capped at 4 MB; a Keychain write failure no longer lists a custom server without its token
- [x] T9 Agent mode UI (9f3cc2c, 027ce22, 235ff42, fc8627a, 5dc89b2): tools on per thread by default (`ThreadRecord.toolsDisabled`, composer "+" Tools switch), stock Form for Settings › Integrations (AnyRouter, built-in tool switches, custom servers with swipe to remove, per-server tool list), tool rows with readable titles that expand to arguments and result, approval as a confirmation dialog, UI test for the tool row
- [x] T10 Live tool list (31 tools, 26 Firecrawl) as a test fixture; AnyRouter tools judged read-only by annotation or name, only those start on, the rest ask each time; `fetch_url` prefers the Firecrawl scrape tool and falls back to the device; `read_attachment` reads the attachments of the current chat
- [x] T11 Data-out rules for tools that run unasked: an address goes out without asking only when its host is in the user's own messages or attachments of this chat, otherwise a dialog shows the full address (no "always allow"); a `web_search` asks when its query repeats 80 or more characters of the user's text, other searches stay silent (decision: blocking every search would make the tool useless, and a short quote leaks little); `research_*` tools ask like the other acting tools. Fetching a link out of a search result therefore asks each time
- [x] T12 (77aac63, e09c542) Tool sources (one table, `Engines/Tools/ToolSourceCatalog.swift`): on device, public web services that need no account or key, AnyRouter, custom. Exa (search and read pages) starts on when the user is signed out or the model runs on the device; DeepWiki and Microsoft Learn are opt-in. Tools of public services are pinned in the app (short text, no `tools/list` round trip, no token ever sent), carry a first-use note naming the recipient, and keep the address and long-passage checks. `ToolProfile`: on-device models get at most 8 tools, 160-character descriptions and answers cut at 6000 characters; cloud models are unchanged. Settings › Integrations has four sections, a switch per source and per tool, and the composer menu shows the same icons. Anonymous AnyRouter MCP needs a server change: proposal in duyet/anyrouter#8469. Checked live on 2026-11-27 with `initialize` and `tools/list`: **added** Exa `mcp.exa.ai/mcp` (docs state a free no-key rate limit), DeepWiki `mcp.deepwiki.com/mcp` (docs: free, no authentication), Microsoft Learn `learn.microsoft.com/api/mcp` (docs: no authentication). **Rejected**: Jina `mcp.jina.ai` (lists tools, every call answers "set your API key"), Parallel search (401), AnyRouter itself (401 without a token), Context7 (answers without a key but its docs now point to OAuth and API keys, so free keyless use is not promised), Hugging Face (answers without a key, no keyless terms found), GitMCP (works, overlaps DeepWiki), Cloudflare docs (works, too narrow for a chat app), DuckDuckGo and similar (no official keyless API, scraping), Tavily, Brave, Firecrawl, Perplexity, Kagi (key required). Local models are not wired yet: they have no tool loop (T7); a local engine only has to read `ToolHost.specs` and call `execute`, and `ToolProfile.compact` already applies to them.
- [x] T14 @ plugins and files in the composer: typing @ (or "Plugins" in the + menu) opens a glass list above the field (`Features/Chat/ComposerMention.swift`, `MentionSuggestions.swift`). Rows are the plugins that are on and the newest files of the chat, with "Plugin" or "File" in grey; the list filters as the user types and the keyboard stays up. A choice becomes a removable chip and, for the next message only, makes that source the only one offered (`ToolContext.forcedSourceIDs`, even if its switch is off) and adds one sentence to the request naming it; the saved message stays as typed. Settings › Integrations rows already carry their icons.
- [x] T15 Web search for local models now (`Features/Chat/WebGrounding.swift`): GGUF and MLX models have no tool loop (T7), so when Exa search is on and the message looks like it needs fresh information (a pure classifier: search requests, "latest", "today", news, prices, weather, years from 2024; never code, never texts over 500 characters) the chat runs Exa search with the message itself through the same host as a model's own call (first-use note, address and long-passage checks, result cap), puts the top 3 results (title, address, 500-character snippet) in front of the question for that request only with a citation instruction, and shows the same "Searched the web for …" row in the reply. Offline it says so and does not search. Remove it per engine when T7 lands. ToolProfile is the only tool cap: Apple 4 (clock, calculator, search, one page reader), local 8; the Apple engine adds no second cap.
- [x] T13 Apple Foundation Models and the time question: the date tool no longer names the device time zone (the small model talked about a city guessed from the zone id), answers one plain sentence, Apple gets 4 tools with the date tool and calculator first plus a short instruction to answer from the tool result; agent-loop scenario tests with a scripted model; on-device eval list in `Tests/Engines/Apple/Fixtures/apple-tool-evals.json` that skips off device
- [ ] T7 Local GGUF and MLX tool calling (Later): needs chat-template tool rendering and parsing of the model's tool-call tokens per model family

## Local agent (device tools)

Research: [docs/research/local-agent.md](docs/research/local-agent.md) (2026-11-26). Keep the engine-owned loop with host-owned approval and execution; add device tools as `BuiltInTool` conformances; ship read-only tools first. Each item is a small push to main.

- [ ] LA1 `BuiltInTool` gets a side-effect class (`read`, `sensitiveRead`, `write`, `external`) and an optional permission; `AgentToolHost` asks per class (writes and external calls every time, no "always allow")
- [ ] LA2 `DevicePermission` broker (status, request, Settings link) and Settings › Integrations › "On this device" with per-tool switch and status; sensitive tools off by default; our sheet before the system prompt, never at launch
- [ ] LA3 `ocr_image` (Vision text and document recognition on the chat's image attachments, no permission)
- [ ] LA4 `calendar_search` and `reminders` search (EventKit full access, 20 results, title/time/place only)
- [ ] LA5 `reminder_create` and event creation behind a confirmation card with the exact payload (event through `EKEventEditViewController`)
- [ ] LA6 `contacts_lookup` (one field per call, limited-access aware, `ContactAccessButton`)
- [ ] LA7 `place_search` (MapKit) and `weather` (WeatherKit, approximate location); operator enables the WeatherKit capability
- [ ] LA8 `translate_text` (Translation, installed languages; "not installed" comes back as a tool error)
- [ ] LA9 Taint rule in `ExfiltrationGuard` (after a sensitive read, outbound tools ask for the rest of the turn), spotlighting of tool output for every engine, one-time notice when a sensitive result goes to a cloud model
- [ ] LA10 Tool selector (groups, at most 4 tools for Apple and local engines), lower `AppleDynamicTool.maxTools` from 8 to 4, result budget from `tokenCount(for:)` on 26.4 and later, 4 rounds on device engines
- [ ] LA11 Tool-calling eval set (about 20 prompts per engine) in `model-smoke.yml`; no engine gets tools on by default without a pass
- [ ] LA12 `AskAnyRouterIntent` plus `AppShortcutsProvider` (iOS 26, no entitlement): text in, answer out, read tools only, `requestConfirmation` for anything else
- [ ] LA13 `run_shortcut`: user-registered shortcut names, `shortcuts://run-shortcut` with x-callback, loop suspends and resumes, asks every time
- [ ] LA14 T7 for MLX first (mlx-swift-lm tool call processor, strict validation, at most 3 tools), GGUF after `common/` is built or a Swift parser exists
- [ ] LA15 Later: Siri AI tool-intent variant (`@AppIntent(.tool)`, iOS 27.3, internal TestFlight only, not usable from App Store builds; it removes App Shortcuts from Siri)
- [ ] LA16 Later: Core Spotlight index of chat threads and a recall tool

Entry points (reach AnyRouter from anywhere on the phone; owner sonnet-medium-local-agent):

- [x] LA17 (9288e3c) "Ask AnyRouter" App Intent and App Shortcuts (iOS 26, app target, no extension): `AskAnyRouterIntent(text, preset, sendNow)` opens a fresh chat with the text in the composer and the preset applied, or sends it; "Fix my English with AnyRouter"; `PresetEntity` from `PresetStore`. Supersedes the open-the-app part of LA12 (an answer returned to Shortcuts stays in LA12)
- [x] LA18 (6819aaa; the @/plugin list entry waits for sonnet-high-public-tools) Reply helper: built-in "Reply to this" with tone (Polite, Short, Friendly, Formal) and language (Same, English, Vietnamese) pickers; in the launcher row and the @/plugin list; Copy button copies the answer only
- [x] LA19 (7a24e71; the Share route comes with LA22) Read a photo: composer + menu (Camera, Photos) and Share run on-device Vision text recognition (vi, en) into the composer, with presets Translate, Split this bill, Summarize
- [x] LA20 (44bc847) Offline mode: `NWPathMonitor`; offline skips AnyRouter models and web tools ("Offline"), the picker suggests the installed local or Apple model, a chat note says a tool was skipped
- [x] LA21 (df9b363) Control Center and Lock Screen controls (`ControlWidget`, new widget extension `dev.anyrouter.app.controls`): New chat, Voice, Paste and fix, through the LA17 intent. Edits `project.yml`
- [x] LA23 (1618db2) Headless Shortcuts actions that return a string without opening the app: Run preset on text, Summarize, Translate, Ask with model (ModelEntity); New chat and Start voice (starts dictation) as App Shortcuts for the Action Button. Offline: a cloud default gives way to a device model, an asked-for cloud model is refused
- [x] LA22 (b48900a; App Group availability unverified on a device, see docs/sideload.md) Share extension "Ask AnyRouter" (text, URL, PDF, image) through the App Group `group.dev.anyrouter.app`; degrades with a clear message where App Groups are not available (free Apple ID sideload). Edits `project.yml` and entitlements

## Backlog (after milestone 1; pick one, tick it, add a PR number)

- [ ] F1 Device smoke test on iPhone + iPad: AnyRouter sign-in, Apple FM chat, GGUF download + chat, MLX download + chat. Record results in the status log.
- [ ] F2 Reasoning stream: add `ChatDelta.reasoning(String)` to Core, emit it from GGUF/MLX (Qwen3 `<think>`) and AnyRouter (`reasoning` deltas), show a collapsible thinking block.
- [ ] F3 GGUF KV-cache reuse between turns (only feed the new suffix).
- [x] F4 (bf03a16) Newer llama.cpp: our own xcframework (device + Simulator slices) built in CI from a pinned tag, replacing the b10456 pin (D18). Pin is b12603. `common/` is not built yet; see D14 for what that unlocks (speculative decoding).
- [ ] F5 Bundle Inter (OFL) for closer UI parity; syntax highlighting in code blocks.
- [ ] F6 Vision: image attachments for AnyRouter vision models and Gemma 3 4B (VLM) via MLXVLM.
- [~] F7 Mac: "Designed for iPad" on Apple silicon is in (D22): View > Toggle Sidebar (Ctrl Cmd S), File > New Chat, 820x560 minimum window, "this Mac" in fit sentences, `mac.yml` builds for the Mac destination and captures five screens as Mac-*.png (nightly, not yet run). Left: a native macOS destination, which needs a macOS slice of llama.xcframework and UIKit-free window and keyboard code.
- [x] F15 Prompt presets: starter questions on the empty chat (tap fills the composer, long-press sends), composer presets sheet, custom presets in Settings (#28)
- [x] F8a (#23) Screenshot capture: demo data mode (`-ARDemoData YES`), `AnyRouterUITests`, `screenshots.yml` uploads PNGs for iPhone and iPad, light and dark.
- [ ] F8b Compare the screenshots against the reference mobile screenshots.
- [ ] F8c UX scorecard: `docs/ux-rubric.md` (HIG rubric, 0-5 per criterion, versioned), `scripts/ux-score.py` scores every screenshot with a deterministic scorer (accessibility audit, native ratchet count of the owning files, pixel checks) and a vision judge (AnyRouter API, secret ANYROUTER_E2E_API_KEY, two runs, spread), `ux-score.yml` runs it on Linux after Screenshots and Verify UI on main and writes the table, the delta against the last main run and the five worst issues with owners to the job summary. Report only; a ratchet comes after two weeks of numbers. The judge needs the repo secret ANYROUTER_E2E_API_KEY (same as F21, not set yet: `gh secret list` shows only SMOKE_HF_*); without it the scorecard is deterministic only and says so. Mac: the scorer takes the device tag `mac` (a `Mac-<light|dark>-<screen>.png` name or `--device mac`).
- [x] F16 Home screen: mesh-gradient empty chat (light and dark palettes, static under Reduce Motion), preset chips above the composer, round "+" menu (photo, camera, file disabled as Coming soon; "Enable thinking" for reasoning models). The thinking flag is stored per thread. (#36)
- [ ] F17 Engines read `ThreadRecord.thinkingEnabled` (Qwen3/Gemma 4 chat template switch, AnyRouter `reasoning` request option); only the flag is persisted today.
- [x] F9 Real-model smoke in CI: `model-smoke.yml` runs the smallest catalog GGUF through `GGUFEngine` on the Simulator, plus installer, download manager and Apple Foundation Models availability. MLX is device only. (#18)
- [x] F10 Gemma 4 E2B and E4B (Apache-2.0) in the bundled catalog: GGUF (official QAT Q4_0, llama.cpp b10456 already has the `gemma4` arch) and MLX 4-bit (mlx-swift-lm 3.33 already has `gemma4`). Own Gemma 4 prompt formatter (llama.cpp's template list cannot apply its jinja template), hidden thinking channel, `model_id` input on `model-smoke.yml`, MLX template render check. (#25)
- [x] F11 (ceb8cfa) Shared model catalog on GitHub: `catalog/models.json` (bundled offline fallback, fetched with ETag at launch and on pull-to-refresh) and `catalog/dev-models.json` (Settings switch), `scripts/catalog-add.sh` / `catalog-check.sh` / `catalog-memory.sh`, `catalog.yml` CI check against Hugging Face, `docs/catalog.md`. In `models.json`: Qwen 3.5 0.8B/2B/4B (0.8B proven by model-smoke on b12603). Staged in dev: LFM2.5 1.2B and VL, LFM2 700M, SmolLM3 3B, Gemma 4 mobile builds, Bonsai 8B (promote to `models.json` after a model-smoke run each).
- [x] F12 (72e06f6) Fit check and live memory: `FitPlanner` (weights + KV cache + 1 GB overhead against the process limit, mixture-of-experts from mmap, context auto-pick), GGUF header reader (local files and ranged reads of Hub repos), fit badges, "needs ~X GB", download warning, memory menu and unload in the chat header.
- [ ] F13 Run a 26B looped-core mixture-of-experts GGUF (6.9 GB IQ1_S) on an 8 GB phone: llama.cpp b12603, mmap load, GPU layers tuned to the Metal working set, context auto-picked. Simulator proof through `model-smoke.yml` (`hf_repo` + `hf_file`, or the `SMOKE_HF_*` secrets) still to run.
- [x] F18 (ad70f7d) Create account and onboarding: Create account opens the sign-up page in the same `ASWebAuthenticationSession` with the authorize URL as `redirect_url`, so a new user comes back signed in (no second login). Welcome page (three sources, Continue with AnyRouter, Create account, Use on-device only), `SignInFlow` state machine, Settings "Verify your email" row from `/me` `email_verified`.
- [ ] F19 Coverage: the unit job gates 100% lines on Core and on logic, stores, view models, the AnyRouter engine, the catalog and the download state machine (`scripts/coverage-gate.sh`, exclusions in `scripts/coverage-exclusions.txt`; part 1, landed, summary lists uncovered functions). Part 2 open: XCUITest flows for every screen run in a separate ui-tests job on iPhone and iPad.
- [ ] F20 Adopt the first-party mobile client and the universal-link sign-in callback once the server side ships (tracked privately).
- [ ] F21 UI E2E against prod AnyRouter, gated on the repo secret ANYROUTER_E2E_API_KEY (skipped with a summary note when absent, never on fork PRs, key never printed): model list loads, pick auto, send a question, streamed answer contains the result, invalid key shows the signed-out state, sign out clears the key.
- [x] F22 SSE usage from include_usage and anyrouter_metadata: the request sends `stream_options.include_usage`, unknown top-level fields are ignored, token counts fall back to `anyrouter_metadata.usage`; fixture in `Tests/Engines/AnyRouter/ProdStreamShapeTests.swift`.
- [ ] F23 CI speed and cost: build once and test many in one macOS job, compilation caching, path-aware jobs, Xcode-free checks on Linux (device-ipa already runs after CI and only for app changes).
- [ ] F24 UI test matrix: one iPhone per push, nightly device matrix, Dynamic Type and landscape, flows from the list in the coverage lane.

## Local inference roadmap

Plan for advanced on-device inference (research date 2026-11-26). Docs only: no feature code lands with this section.
Engines today: GGUF through the official `llama.xcframework` (pinned b10456, D18) and MLX through `mlx-swift-lm` 3.33.0.

What the research found, and why it sets the order:

- **The official xcframework is `libllama` only.** Upstream `build-xcframework.sh` sets `LLAMA_BUILD_COMMON=OFF`. All speculative decoding (draft, MTP, DFlash, EAGLE-3) and the `--reasoning-preserve` flag live in `common/` and `tools/server`, so the app cannot reach them. MTP also needs an internal header (`llama-ext.h`). Any GGUF speculative feature therefore waits for **F4** (own xcframework from an official tag, with `common/` built and a small C shim for Swift).
- **Newer releases have no Simulator slice.** b12756 ships `ios-arm64` and `macos` only, so F4 is also what lets us move the pin.
- **`mlx-swift-lm` 3.33.0 already has** speculative decoding with a draft model, MTP drafters (Gemma 4 assistants, Qwen 3.5 and 3.8), and a TurboQuant KV cache. It has **no DFlash** (issue #606 is open for DFlash2) and **no EAGLE-3**.
- **Drafter weight cost differs a lot.** MTP heads are small (Gemma 4 E2B and E4B about 190 MB, Qwen 3.5 4B about 261 MB). A DFlash draft for a 4B target is about 1.27 GB. EAGLE-3 drafters for Gemma 4 exist only for the 26B-A4B and 31B targets (about 4.5 GB), which no phone can hold.
- **Current engines block three features.** GGUF builds a new context per answer with a fixed `n_ctx` and no flash-attention or KV-type fields. MLX uses a fixed rotating `maxKVSize` of 4096, and the TurboQuant cache cannot be combined with a rotating cache.
- **iOS limits.** No JIT and no downloaded executable code (model weights are fine). MLX compiles its custom Metal kernels from source at run time (`MLXFast.metalKernel`): this is shader source, not native code, but confirm with the first TestFlight upload. GPU work stops when the app is backgrounded, so generation is foreground only. Thermal state must be recorded with every benchmark.

### Verdicts

| ID | Feature | Engine | Verdict | Dependency and reason |
|---|---|---|---|---|
| L1 | Open-weight families (Llama, Gemma, Qwen, Mistral, Phi, others) | both | **Now** | Catalog entries plus chat-template checks. MLX supports `mistral3`/`ministral3` and `phi3` model types. |
| L2 | MTP speculative decoding, Gemma 4 | MLX | **Now** | `mlx-swift-lm` >= 3.33.0 (have). GGUF: Later, needs F4. The first upstream Gemma 4 MTP PR (llama.cpp #23398, in b10456) covered the 31B and 26B-A4B drafters only; re-check E2B and E4B before starting. |
| L3 | DFlash block-diffusion decoding | GGUF | **Later** | Upstream since b9831 (PR #22105, in b10456) but only in `common/`: needs F4. 1.27 GB draft for a 4B target; fits only 12 GB+ devices and iPad. Pin must include the fix for #32526 (wrong acceptance, closed 2026-11-18). No MLX Swift port. |
| L4 | Flash attention on / off / auto | GGUF | **Now** | `llama_context_params.flash_attn_type` is in b10456. MLX always uses fused attention: hide the toggle there. Quantized V cache needs flash attention on. |
| L5 | Reasoning-context tracking | both | **Now** | Core `ReasoningTracker` (P2) and backlog F2. No upstream dependency: the app tracks `<think>` tags itself. |
| L6 | Auto context expansion with overflow notice | both | **Now** | Core `ContextPolicy` (P3). GGUF: choose `n_ctx` per answer from a memory budget. MLX: replace the fixed `maxKVSize`. |
| L7 | EAGLE-3, Gemma 4 | MLX | **Not applicable on iOS** | Only 26B-A4B and 31B drafters exist, and no Swift implementation exists (Python `mlx-vlm` only). Upstream llama.cpp has `draft-eagle3` (PR #18039, in b10456): revisit with F4 if a phone-size drafter appears. |
| L8 | MTP, Qwen 3.5 / 3.6 / DeepSeek V4 | MLX | **Now** for Qwen 3.5 small sizes; **Not applicable** for DeepSeek V4 | 3.33.0 has Qwen 3.5 and 3.8 MTP. Qwen drafters need greedy sampling (temperature 0), otherwise the engine falls back. Add Qwen 3.6 when a phone-size checkpoint exists. DeepSeek V4 is not in `mlx-swift-lm` and is far beyond phone memory. |
| L9 | TurboQuant KV cache (turbo3 / turbo4) | GGUF | **Later** | Not in ggml-org (issue #20977 closed as not planned, 2026-08-20). Only in MIT-licensed community forks (for example `TheTom/llama-cpp-turboquant`, with Metal kernels). Needs F4 plus D14. The forks' own benchmark shows lower tok/s than f16 KV with MTP on Gemma E4B (67.8 vs 94.3), so it is a memory feature, not a speed feature. Interim: q8_0 and q4_0 KV under L4. |
| L10 | TurboQuant KV cache | MLX | **Now**, experimental, off by default | `KVCacheConfiguration(strategy: .turboQuant(...))` in 3.33.0. Cannot combine with a rotating `maxKVSize`: needs L6 first. |

### Shared prerequisites (Core, lane A reviews)

Added as defaults-safe `Codable` fields so stored settings still decode. `ChatEngine` does not change.

```swift
enum FlashAttention: String, Codable, Sendable { case auto, on, off }          // GGUF only

enum KVCacheScheme: Codable, Sendable, Equatable {                            // L4, L9, L10
  case f16, q8_0, q4_0                                                         // GGUF and MLX affine
  case turboQuant(bits: Double)                                                // MLX only until L9
}

enum SpeculativeMode: Codable, Sendable, Equatable {                          // L2, L3, L8
  case off
  case mtp(blockSize: Int)        // MLX now, GGUF after F4
  case dflash(blockSize: Int)     // GGUF after F4
}

struct ContextPolicy: Codable, Sendable, Equatable {                          // L6
  var preferred: Int = 4096                 // tokens
  var ceiling: Int? = nil                   // nil = min(trained length, memory budget)
  var onOverflow: Overflow = .expand        // .expand, .trimOldest, .fail
  enum Overflow: String, Codable, Sendable { case expand, trimOldest, fail }
}

enum ContextEvent: Sendable, Equatable {                                      // new case ChatDelta.notice(ContextEvent)
  case expanded(from: Int, to: Int)
  case trimmed(droppedMessages: Int)
  case exceeded(limit: Int)
}

struct InferenceSettings: Codable, Sendable, Equatable {                      // GenerationParams.inference
  var flashAttention: FlashAttention = .auto
  var kvCache: KVCacheScheme = .f16
  var speculative: SpeculativeMode = .off
  var context = ContextPolicy()
  var reasoning: ReasoningHistory = .strip   // .strip (default), .keep when the template reads reasoning
  func validated(for model: ModelDescriptor) -> InferenceSettings   // drops what the model cannot do
}

struct ReasoningTracker: Sendable {                                           // L5, pure state machine
  init(tags: (open: String, close: String))        // detected from the chat template
  mutating func feed(_ chunk: String) -> [ChatDelta]   // .reasoning / .text, tags may split across chunks
  var reasoningTokens: Int { get }
}
```

Per-model support is a set of strings in the existing `ModelDescriptor.capabilities`: `reasoning`, `spec-mtp`, `kv-turboquant`. The catalog gains an optional `companions` list per entry (`role` such as `drafter` or `mmproj`, `repo`, `file`, `sizeBytes`, `sha256`; see Multimodal roadmap); the downloader fetches a drafter next to its target and the hub lists it as part of the same model. `validated(for:)` is the one place that enforces the rules: V-cache quantization requires flash attention, `.mtp` needs a drafter on disk and a memory fit, Qwen drafters need temperature 0, TurboQuant excludes a rotating cache.

Memory model used by L4, L6, L8, L10: KV bytes per token = 2 x n_layer x n_head_kv x head_dim x bytes per element (f16 2, q8_0 about 1.06, q4_0 about 0.56), read from GGUF metadata (`llama_model_n_layer`, `llama_model_n_head_kv`, `llama_model_n_embd`) or the MLX config. Budget = `os_proc_available_memory()` at load, times 0.6 as a starting guess; tune from F1 device runs. Weights, KV and drafter must all fit inside it.

### Measuring (every item that claims a speedup or a saving)

Explain the number. Same model file, same drafter, same prompt, greedy (temperature 0), 256 prompt tokens and 256 new tokens from a fixed prompt set in the repo. Run cold (first load after a fresh app launch) and warm (second run), 5 runs each. Report median and min to max for decode tok/s, prefill tok/s and time to first token; for speculative modes also the acceptance rate; for all, peak footprint (`task_info` `phys_footprint`) and `ProcessInfo.thermalState` at start and end. Discard a run that starts at `.serious` or hotter. Where: a Settings > Developer Benchmark screen (S4) on the operator's iPhone and iPad (F1 records the results here). The Simulator runs only correctness checks in `model-smoke.yml` (CPU numbers are not device numbers). Vendor claims (30 to 70 percent, 3x, 6x, 4.3x) stay unverified until measured. Gate for turning a speculative mode on by default: median decode gain of at least 20 percent over baseline on a phone with peak footprint inside the budget; otherwise it stays opt-in.

### Sequence (small PRs, each ends in a check)

Core PRs go to lane A's files, engine PRs to lane C's, UI rows to lane D's. S3 (catalog) does not depend on S2 and can start now; S4 can run in parallel with S2.

- [ ] S1 This plan (docs only).
- [ ] S2 Core types above with defaults, `validated(for:)` and unit tests (illegal combinations are dropped, old stored settings still decode). Check: CI unit tests.
- [ ] S3 **L1** Catalog: Ministral 3 3B Instruct (GGUF `mistralai/Ministral-3-3B-Instruct-2512-GGUF`, MLX `mlx-community/Ministral-3-3B-Instruct-2512-4bit`, Apache-2.0), Phi-4-mini-instruct (`unsloth/Phi-4-mini-instruct-GGUF`, `mlx-community/Phi-4-mini-instruct-4bit`, MIT), Qwen3.5 4B (`unsloth/Qwen3.5-4B-GGUF`, Apache-2.0). Golden prompt tests per family (GGUF `PromptBuilder` and the MLX template smoke test) from a template rendered offline. Acceptance: each new entry loads, renders the expected prompt, and answers a one-line prompt in `model-smoke.yml` (GGUF) or on device (MLX).
- [ ] S4 Benchmark runner in `Core` plus the Settings > Developer screen and a JSON export. Acceptance: one run on the Simulator in CI uploads the JSON as an artifact; the screen shows the metrics above.
- [ ] S5 **L4** GGUF: pass `flash_attn_type`, `type_k`, `type_v` from `InferenceSettings`; settings rows for flash attention and KV type (GGUF only). Acceptance: `validated(for:)` drops a quantized V cache when flash attention is off; model-smoke produces non-empty output for `auto`, `on`, `off` and q8_0 KV (output may differ between settings). Measure: decode tok/s and peak footprint, f16 vs q8_0 vs q4_0 KV at 4k and 8k context.
- [ ] S6 **L5** `ReasoningTracker` and `ChatDelta.reasoning` (completes F2), with the collapsible thinking block. History policy `.strip` by default; reasoning tokens counted against the context budget and dropped first. Acceptance: tracker tests for tags split across chunks, nested or missing close tags, and an interrupted stream; a Qwen3 answer shows a thinking block in the UI test.
- [ ] S7 **L6** `ContextPolicy`: estimate prompt tokens, grow `n_ctx` (GGUF) or the KV window (MLX) up to the ceiling, else trim oldest turns or fail; emit `ChatDelta.notice` and show a one-line banner ("Context grew to 8192"). Replaces the fixed MLX `maxKVSize`. Acceptance: unit tests for the planner (fits, expands, hits ceiling, trims); model-smoke with a long prompt expands once and answers; the notice appears exactly once.
- [ ] S8 **L2 and L8 on MLX** Register the Gemma 4 and Qwen MTP drafters at launch, add the catalog `companions` field with role `drafter`, download a drafter with its target, honour `SpeculativeDecodingConfig`/fallback reasons (greedy only for Qwen, memory policy), show "Speculative: on/off (reason)". Acceptance: Gemma 4 E2B and Qwen3.5 4B with drafter produce the same greedy text as without (token parity), device benchmark recorded here. Default stays off until the gate above passes.
- [ ] S9 **L10** TurboQuant KV on MLX behind an "Experimental" row, no rotating cache (needs S7). Acceptance: memory saving and first-256-token divergence versus f16 recorded on device; off by default.

Later (each needs its blocker first): **F4** own xcframework (device and Simulator, `common/` built, C shim) → L3 DFlash, GGUF MTP, GGUF EAGLE-3 (L7), and a decision on L9 forks (D14).

## Multimodal roadmap

Plan for text, vision, audio, image and video models on device (research date 2026-11-26). Docs only. It builds on the Local inference roadmap above (same budget rule, same measuring protocol, same F4).

What the research found, and why it sets the order:

- **Every engine must be a linked library.** An iOS app cannot start helper executables, so server-style engines (a `sd-server`, an audio server, a Python MLX sidecar) are out. Each route below is an xcframework, a Swift package or a system framework.
- **Vision and audio input for GGUF need nothing new.** The official `llama.xcframework` already contains `libmtmd` and ships `mtmd.h` and `mtmd-helper.h` (checked in b10456 and b12756). It handles images and audio through an `mmproj` companion file. Its video decoding is switched off in the Apple build (`MTMD_VIDEO=OFF`), so video means sampling frames in the app and sending them as images.
- **`mlx-swift-lm` 3.33.0 already has `MLXVLM`**: Gemma 4 (with an audio encoder) and Gemma 3, Qwen2-VL, Qwen2.5-VL and Qwen3-VL, SmolVLM2, FastVLM, Idefics3, Mistral3, Pixtral, PaliGemma, LFM2-VL. `UserInput` takes images, video frames and audio. Our MLX engine imports only `MLXLLM` today (backlog F6).
- **Speech has system answers.** `SpeechAnalyzer` and `SpeechTranscriber` (iOS 26.0+) transcribe on device with no app-size cost; `AVSpeechSynthesizer` speaks with system voices. Open models are an opt-in extra, not the base.
- **Image generation is a different job from chat.** Real routes today: Apple Core ML Stable Diffusion, stable-diffusion.cpp (no iOS build published), the MLX Swift `StableDiffusion` example library, and Apple's ImagePlayground. Only the first and last are realistic on a 6 or 8 GB phone.
- **Video generation is not realistic on phones.** The open video models stable-diffusion.cpp runs (Wan 2.1/2.2, LTX 2.x) start at about 5B parameters plus a text encoder and a video VAE.

Model sizes behind the verdicts (Hugging Face file sizes, 2026-11-26):

| Model | Files | Total |
|---|---|---|
| SmolVLM2 500M Video, GGUF | Q8_0 437 MB + mmproj Q8_0 109 MB | about 0.55 GB |
| Qwen2.5-VL 3B, GGUF | Q4_K_M 1.93 GB + mmproj Q8_0 0.85 GB | about 2.8 GB |
| Gemma 4 E2B, GGUF (vision and audio in) | Q4_0 2.84 GB + mmproj Q8_0 0.56 GB | about 3.4 GB |
| Gemma 4 E4B, GGUF | Q4_0 4.59 GB + mmproj | over 5 GB: 12 GB-class iPad only |
| Qwen3-ASR 0.6B, GGUF (speech in) | Q8_0 805 MB + mmproj 379 MB | about 1.2 GB |
| Apple Core ML SD 2.1 base, palettized | split_einsum_v2 compiled, 1.14 GB | 1.14 GB |
| stable-diffusion.cpp SD-Turbo, GGUF | f16-q8_0 2.0 GB | 2.0 GB (licence "other": review first) |
| Whisper (whisper.cpp / WhisperKit) | tiny 75 MiB, base 142 MiB, small 466 MiB | optional |

Fit on 6, 8 and 12 GB devices uses the existing device-fit check and the memory budget from the Local inference roadmap (weights + mmproj + KV must fit). On 6 GB that means SmolVLM2 500M and Qwen2.5-VL 3B; Gemma 4 E2B only if the check passes; E4B is refused.

### Verdicts

| ID | Feature | Engine | Verdict | Dependency and reason |
|---|---|---|---|---|
| M1 | Vision input, photo picker and camera | GGUF (`libmtmd`) and MLX (`MLXVLM`) | **Now** | Pinned b10456 and `mlx-swift-lm` 3.33.0 already carry it. Needs the `mmproj` companion file. |
| M2 | Video understanding (frames into a VLM) | both | **Now**, after M1 | App-side frame sampling (at most 1 frame per second, at most 8 frames, long edge 512 px). No upstream change. |
| M3 | Audio input to the LLM (Gemma 4 E2B/E4B, Qwen3-ASR) | GGUF now; MLX later | **Now** for GGUF Gemma 4 E2B; MLX **Later** | `libmtmd` audio projectors are in the pinned xcframework. MLX has a Gemma 4 audio encoder, but the audio input path is not verified. Check the maximum clip length per model before shipping. |
| M4 | Speech-to-text dictation | system | **Now** | `SpeechTranscriber`, iOS 26.0+. WhisperKit (MIT, Core ML) is a **Later** fallback for locales the system lacks. |
| M5 | Text-to-speech, system voices | system | **Now** | `AVSpeechSynthesizer`. Zero download. |
| M6 | Neural text-to-speech (Soprano 80M, Pocket TTS, Qwen3-TTS 0.6B, Kokoro) | MLX | **Later** | Optional "natural voice" pack through the MIT-licensed MLX Audio Swift package (iOS 17+). Needs measured real-time factor and memory first. |
| M7 | System image generation | system | **Now**, cheap first step | ImagePlayground (`ImageCreator` iOS 18.4+, which iOS 27 deprecates in favour of `ImagePlaygroundViewController`). No download. Apple Intelligence devices only; styles are Apple's. |
| M8 | Image generation, Core ML | Core ML | **Now**, after M1 to M5 | `apple/ml-stable-diffusion` (MIT code), SD 2.1 base palettized (OpenRAIL++ weights). Apple's 2023 benchmark shows 7.9 to 18.5 s per 512x512 image on iPhone 12 mini to 14 Pro Max and 7.0 s on iPad Pro M2. Those are old numbers from iOS 17 betas: re-measure. |
| M9 | Image generation, stable-diffusion.cpp or MLX image models | GGUF / MLX | **Later** | No iOS build is published: needs our own xcframework (same job as F4). Z-Image-Turbo and FLUX-class models are a 6B transformer plus a 4B text encoder: iPad 16 GB at best. MLX `StableDiffusion` covers SD 2.1 and SDXL-Turbo; SDXL-Turbo is 6.9 GB in fp16, too large for phones. |
| M10 | Video generation | none | **Not on iOS phones today** | About 5B parameters minimum, memory and time far beyond a phone. Revisit only if a model under 1B appears, then measure on iPad first. Video understanding (M2) covers the useful part. |
| M11 | Music and sound-effect generation | none | **Not planned** | No phone-size model verified. |

### Core contract impact (lane A reviews; all fields default so stored data still decodes)

`ChatEngine` does **not** change: attachments ride on the message, and an engine rejects a part it cannot take. Image generation and speech get their own protocols because their input and output are not text deltas (progress, previews, audio streams).

```swift
struct AttachmentRef: Codable, Hashable, Sendable {     // file in Application Support, excluded from backup
  var id: UUID; var kind: Kind; var relativePath: String; var byteCount: Int64
  enum Kind: String, Codable, Sendable { case image, audio, videoFrame }
}

enum MessagePart: Codable, Hashable, Sendable {         // ChatMessage.parts, default []
  case image(AttachmentRef)
  case video(frames: [AttachmentRef], durationSeconds: Double)   // sampled frames, original not sent
  case audio(AttachmentRef, durationSeconds: Double)
}                                                       // ChatMessage.content stays the text

enum ModelKind: String, Codable, Sendable { case chat, speechToText, textToSpeech, imageGeneration }

struct Companion: Codable, Hashable, Sendable {         // catalog; generalizes the drafters list
  var role: Role                                        // .mmproj, .drafter, .vae, .textEncoder
  var repo: String; var file: String; var sizeBytes: Int64; var sha256: String?; var required: Bool
  enum Role: String, Codable, Sendable { case mmproj, drafter, vae, textEncoder }
}
// ModelDescriptor gains: kind (default .chat). ModelSource gains: .coreml, .system (and .sdcpp with M9).
// capabilities strings: "vision", "audio-in", "video-frames" (already: "chat", "tools", "reasoning").
// Catalog entry gains: kind, companions: [Companion], license (exists).

protocol ImageGenerationEngine: Sendable {
  func availableModels() async throws -> [ModelDescriptor]
  func generate(model: ModelDescriptor, request: ImageRequest) -> AsyncThrowingStream<ImageEvent, Error>
}
struct ImageRequest: Codable, Sendable { var prompt: String; var negativePrompt: String?
  var width: Int; var height: Int; var steps: Int; var guidance: Double; var seed: UInt64?; var count: Int }
enum ImageEvent: Sendable { case progress(step: Int, of: Int); case preview(AttachmentRef); case done(AttachmentRef, seed: UInt64) }

protocol SpeechRecognizer: Sendable {                   // M4, later WhisperKit
  func transcribe(microphone locale: Locale) -> AsyncThrowingStream<TranscriptEvent, Error>  // .partial(String), .final(String), .assetDownload(Double)
}
protocol SpeechSynthesizer: Sendable {                  // M5, later M6
  func speak(_ text: String, voice: VoiceDescriptor?) -> AsyncThrowingStream<SpeechEvent, Error>  // .started, .finished
  func stop()
}
```

`EngineRegistry` gets `register` overloads for the three new protocols; the UI asks it by kind and never branches on source. `ModelDescriptor.capabilities` decides whether the composer shows the photo, camera and microphone buttons. The downloader fetches `required` companions with their model and shows them as one item in the hub.

iOS limits for this section: the app ships no executable code (weights are data, fine); the camera, microphone and speech-recognition usage strings go in `project.yml` with the PRs that need them (check whether `SpeechTranscriber` needs the speech-recognition string); recording and generation are foreground only (GPU work stops in the background); record thermal state with every benchmark; show each model's licence from the catalog before download.

### Measuring

Same rules as the Local inference roadmap: fixed inputs in the repo, cold and warm, 5 runs, median and range, peak footprint, thermal state, device named. Per feature: **vision** time to first token with one image of fixed size plus peak footprint; **speech-to-text** real-time factor and word error on a fixed 30 s clip; **text-to-speech** time to first audio and real-time factor; **image generation** seconds per image at fixed size, steps and seed, plus peak footprint; **audio-in** time to first token for a fixed clip. Simulator CI checks correctness only (CPU).

### Sequence (small PRs, each ends in a check)

Starts after S2 (Core types). Docs-only PRs skip the macOS build.

- [ ] R1 Core: `AttachmentRef`, `MessagePart`, `ModelKind`, `Companion`, catalog fields, attachment storage and SwiftData link, tests that old stored messages and catalogs still decode. Replaces the `drafters` field named in S8 with `companions` (role `drafter`).
- [ ] R2 **M1 GGUF** `mtmd` bridge (`mtmd_init_from_file`, `mtmd_tokenize`, `mtmd_helper_eval_chunks`), companion download, catalog entries (SmolVLM2 500M, Qwen2.5-VL 3B, Gemma 4 E2B with mmproj), photo picker and camera in the composer (button shown only for `vision`). `mtmd` aborts the whole process on a projector type it cannot build (seen as SIGABRT in server form), which in the app would crash it: read `clip.projector_type` from the mmproj header with `gguf.h` (shipped in the xcframework) and check it against an allowlist before `mtmd` init; on a miss, run text-only and say so. Acceptance: model-smoke runs SmolVLM2 500M on a fixture image of one solid colour and the answer names it; a text-only model hides the button; a test mmproj with an unknown projector type gives text-only, not a crash.
- [ ] R3 **M1 MLX** add the `MLXVLM` product, pass images through `UserInput`, catalog entries for Gemma 3/4, Qwen2.5-VL, SmolVLM2 (4-bit). Acceptance: on device only (MLX has no Simulator GPU): one image Q&A per model, recorded in F1.
- [ ] R4 **M2** `FrameSampler` (AVAssetImageGenerator): at most 1 frame per second, at most 8 frames, long edge 512 px. Acceptance: unit test on a generated 3 s clip checks frame count and size; model-smoke asks one question about a two-colour clip.
- [ ] R5 **M4 and M5** `SpeechRecognizer` on `SpeechTranscriber` (microphone button, partial text in the composer, language asset download state) and `SpeechSynthesizer` on `AVSpeechSynthesizer` (read aloud on a message). Acceptance: fake-engine tests of the protocols; device check of both, word error recorded.
- [ ] R6 **M3** audio input through `mtmd` with Gemma 4 E2B (record or pick a clip, `.audio` part, clip-length limit from the model). Acceptance: model-smoke on a fixture spoken clip; the answer contains the spoken word.
- [ ] R7 **M7** ImagePlayground sheet behind an availability check; saved results become `.image` attachments.
- [ ] R8 **M8** `ImageGenerationEngine` plus `CoreMLDiffusionEngine` (`StableDiffusionPipeline`, `reduceMemory` on), an Images screen with progress and a gallery, SD 2.1 base palettized as the first model. Acceptance: fake-engine tests in CI; device benchmark (seconds per image, peak memory, 512x512, fixed seed) recorded here.

Later (each needs its blocker first): M6 neural voices (measure first), M9 stable-diffusion.cpp or MLX image models (own xcframework), WhisperKit fallback, MLX audio input. Not planned: M10, M11.

## Voice roadmap

Research date 2026-11-27. Scope: iOS 26 on device, speech to text (STT) with language detection for English, Vietnamese and others, and text to speech (TTS). Licences are checked for shipping in an App Store app.

### Findings

**STT, system.**
- `SpeechTranscriber` (iOS 26.0+) takes one locale per instance and has no language detection. "Automatic language management" in the WWDC25 session means model assets, not audio language identification. [WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/), [fmasi/parley#147](https://github.com/fmasi/parley/issues/147).
- Vietnamese is reported in the locale list of later iOS 26 builds (42 locales, 22 languages, as of August 2026) but not in the launch list, and Apple publishes no list. Treat it as a runtime question: ask `SpeechTranscriber.supportedLocales` and `installedLocales`, then `DictationTranscriber.supportedLocales` (same models as keyboard dictation, more locales, less accuracy), then `SFSpeechRecognizer(locale:).supportsOnDeviceRecognition`. [LoroNote](https://loronote.com/en/blog/apple-speechanalyzer-vs-whisper), [Addpipe](https://blog.addpipe.com/apple-speechanalyzer-api/), [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber).
- Confidence is only on final results, not volatile ones (one report), so it cannot drive a live language switch by itself.

**STT, downloads.**

| Engine | Languages | Language detection | Licence | Size | Verdict |
|---|---|---|---|---|---|
| WhisperKit (Core ML) tiny / base / small / large-v3 turbo compressed | about 99 incl. Vietnamese | yes, from audio | MIT code, MIT weights | 77 MB / 147 MB / 217 MB / 627 MB (HF folder sums, 2026-11-27) | **Chosen.** iOS 16+, no other package dependency (the package pulls only swift-argument-parser), so it cannot clash with the swift-transformers pin. Small Whisper is weak in Vietnamese: the Moonshine paper reports 91.9% word error for Whisper Tiny on FLEURS vi, so Vietnamese needs small or larger. |
| whisper.cpp | same | yes | MIT | same weights | Needs our own xcframework (F4 job). WhisperKit covers the same model on Core ML. |
| Moonshine Voice streaming | English, Spanish, German, Arabic, Japanese, Mandarin, Tagalog, **Vietnamese (Tiny Streaming 34M, 9.4% WER)** | no: one model per language | MIT (streaming models); the legacy non-streaming non-English models are non-commercial | 34M to 245M params | **Later.** Best live Vietnamese and English at tiny size, but needs the language first. Pair with WhisperKit detection or the user's pick. Binary xcframework, assets from the vendor CDN. |
| Parakeet TDT v3 (FluidAudio, Core ML) | 25 European languages, no Vietnamese | yes | CC-BY-4.0 weights, Apache-2.0 SDK | about 0.6B | Not chosen: no Vietnamese. |

Sources: [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (Package.swift, README), [whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml), [Moonshine models and licence](https://github.com/moonshine-ai/moonshine/blob/main/docs/models/available-models.md), [Moonshine licence](https://github.com/moonshine-ai/moonshine/blob/main/docs/license.md), [Parakeet v3 Core ML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml).

**TTS, system.** `AVSpeechSynthesizer` voices come from `AVSpeechSynthesisVoice.speechVoices()`; there is no API that lists voices not yet downloaded in Settings, so the app can only offer a "get a better voice" link when the best installed voice for a language is `default` quality. Which Vietnamese voices exist (and their quality tier) is a device check.

**TTS, downloads.**

| Engine | Languages | Licence | Runtime on iOS | Verdict |
|---|---|---|---|---|
| Moonshine Voice TTS (Piper and Kokoro voices, own G2P) | 20 locales incl. **vi-vn**, en-us, en-gb, es, fr, de, it, pt, ja, ko, zh-hans, ar, hi, ru, tr, uk, nl | Library MIT; voice and lexicon data per language README, so each voice is checked before it enters the catalog | Swift package `moonshine-swift` (static xcframework, iOS 15+), `TextToSpeech().language().modelsFrom(dir).onProgress().load()` then `synthesize` | **Chosen**, the only open runtime found with a Vietnamese voice and no GPL phonemizer at run time. |
| Kokoro-82M | en-US, en-GB, es, fr, hi, it, ja, pt-BR, zh. **No Vietnamese** | Apache-2.0 | MLX (mlx-audio-swift, MIT, but pulls its own mlx-swift pin), or through Moonshine | Through Moonshine only. |
| Piper vi_VN (vais1000 medium, 63 MB; training corpus CC BY 4.0, base Hi-Fi TTS 92) | Vietnamese | CC BY 4.0 data | sherpa-onnx or Piper: both phonemize with espeak-ng (GPL-3.0) | Not chosen directly: a GPL phonemizer inside an App Store build is unresolved. |
| MMS-TTS vie (VITS) | Vietnamese | CC-BY-NC 4.0 | any | **Refused**: non-commercial. |
| VieNeu-TTS 0.3B (Qwen3 GGUF plus a neural codec) | Vietnamese | Apache-2.0 | llama.cpp for the LM, codec needs ONNX or Core ML conversion | Later: llama.cpp is already linked, the codec is the work. |
| TTSKit Qwen3-TTS (Core ML, argmax) | 10 languages, no Vietnamese | Apache-2.0 upstream | in WhisperKit's package | **Chosen (V6)** for its 10 languages, 1.1 GB; Vietnamese goes to the System voice. |

Sources: [Moonshine TTS](https://github.com/moonshine-ai/moonshine/blob/main/docs/using/text-to-speech.md), [moonshine-swift](https://github.com/moonshine-ai/moonshine-swift), [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), [Piper vi_VN vais1000 model card](https://huggingface.co/rhasspy/piper-voices/blob/main/vi/vi_VN/vais1000/medium/MODEL_CARD), [VieNeu-TTS-0.3B](https://huggingface.co/pnnbao-ump/VieNeu-TTS-0.3B), [TTSKit](https://github.com/argmaxinc/argmax-oss-swift#ttskit).

### Decisions

1. **Default per device class** (`DeviceClass`, from `FitPlanner`): STT default is the System engine on every class. The recommended Whisper is the largest in the catalog that "runs well" by `VoiceFit`: resident memory (download times 2.2, an estimate until the device eval) at most half of the memory budget the chat models also use. With the standard limit that gives small on 4 and 6 GB, large-v3 turbo compressed on 8 GB and up; the rest stay listed with "Tight" or "Will not fit". Whisper tiny is weak in Vietnamese, so Vietnamese goes to the System engine while tiny is selected (`weakLanguages`).
2. **Language detection.** With Whisper installed and selected, Whisper detects the language from the first second or two of audio and reports it. Without it, the System engine runs the user's candidate locales in parallel (device languages, English, and any the user pinned, at most two) for the first seconds and keeps the one whose text a language recognizer agrees with and whose final confidence is higher. This is a heuristic: its accuracy is an on-device eval item (below). The badge in the composer shows the result and a tap forces a language.
3. **Fallback rule.** System engine always works. A downloaded engine is used only when installed, selected and its `languages` contain the request (STT: the forced or detected language; TTS: the language of each sentence). Otherwise the System engine speaks or listens. The Settings row says "Uses the system voice for Vietnamese" when a TTS model lacks a language the user's device language needs.
4. **Downloads.** Voice models are small multi-file folders from Hugging Face or the vendor CDN, not GGUF or MLX repos, so they use `VoiceModelDownloader`: the same `ModelDownloadState` machine and progress tracker as the LLM downloads, a foreground session, per-file resume, sha256 and size checks, installed under `Application Support/Voice` and excluded from backup.
5. **Permissions.** Microphone and speech recognition are asked at first use only, after a pre-prompt sheet that says audio is processed on the device. `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are in `project.yml`.

### On-device eval list (the CI simulator has no microphone)

- STT: word error and real-time factor on a fixed 30 s English clip and a fixed 30 s Vietnamese clip for the System engine, Whisper base, small and large-v3 turbo compressed, per device class, with thermal state.
- Language detection: 20 short clips (10 English, 10 Vietnamese, 5 mixed) through both detectors; count wrong picks and the seconds until the badge settles.
- TTS: time to first audio and real-time factor for one English and one Vietnamese sentence per engine; whether the best Vietnamese system voice is `default`, `enhanced` or `premium` quality on a clean install.
- Memory: peak footprint with a Whisper model loaded next to a 3B chat model on a 6 GB device.

### Sequence

- [x] V1 (2e501de) Voice seam: `SpeechToText`, `TextToSpeech`, System engines, sentence chunker, language arbiter, `VoiceModel` catalog and fit, fallback resolver, tests.
- [x] V2 (fe56bf3) Dictation in the composer: mic button, live partial text, level meter, language badge, permissions sheet, Info.plist strings.
- [x] V3 (6c0f843) Spoken replies: speaker button, "Read replies aloud", sentence streaming, stop on new input.
- [x] V4 (2123b36) Settings › Local Models › Voice: Speech to text and Text to speech sections, Get and Delete, default, Test voice.
- [x] V5 (4bce970) `WhisperKit` STT engine and catalog entries (tiny, base, small, large-v3 turbo compressed). Read from the v1.1.1 source: with `modelFolder`, `tokenizerFolder` set to the install folder and `download: false`, the tokenizer is found at the folder root (`ModelUtilities.loadTokenizer` search order), so the four files already there are enough; if loading it fails WhisperKit falls back to a Hub download, so a damaged tokenizer.json needs Delete and Get again. WhisperKit carries its own tokenizer copy inside its ArgmaxCore module (no swift-transformers dependency). Its `AudioProcessor` sets its own audio session category when recording starts. Not measured: load time, memory and latency per model (on-device eval list above).
- [x] V6 (86c7c3e) TTSKit Qwen3-TTS: `ttskit-qwen3-0.6b` catalog entry (32 files, 1,102,450,148 bytes, every file pinned to a commit with sha256) and `TTSKitTextToSpeech`. Read from the v1.1.1 source: `TTSKitConfig(modelFolder:, tokenizerFolder:, download: false, load: true)` runs with no network. The folder holds `qwen3_tts/<component>/12hz-0.6b-customvoice/<variant>/*.mlmodelc` with the variants `Qwen3VariantDefaults` gives for 0.6B (they do not change by platform; 1.7B is macOS only and not offered): code_decoder W8A16-stateful, multi_code_decoder W8A16-multifunction, speech_decoder W8A16-multifunction, text_projector W8A16, both embedders W16A16. The tokenizer is `tokenizer.json` and `tokenizer_config.json` of Qwen/Qwen3-0.6B at the folder root (else TTSKit fetches them from Hugging Face). `TTSKit.play` plays through its own AVAudioEngine and returns when the audio has drained; cancelling the task stops generation at once, and the backend then shuts the audio engine. Errors are `TTSError`, mapped to `VoiceError.audioFailed`. Weights licence: the Qwen model card says Apache-2.0; argmax's Core ML card states none. Not measured: load time, memory (the catalog sets no `residentBytes`, so fit uses download times 2.2), first-audio latency, how the non-native speakers sound for German, French, Russian, Portuguese, Spanish and Italian (they use the English speaker). Each sentence is a separate `play`, so there is a gap between sentences.
- [ ] V6b (Later) Moonshine TTS voices, mainly for Vietnamese. Moonshine's voice data is licensed per language and its runtime voice list was not read, so no Vietnamese voice licence could be verified. Vietnamese keeps using the System voice.
- [ ] V7 (Later) Moonshine streaming STT for Vietnamese and English after the language is known; VieNeu-TTS through llama.cpp.

## Accessibility audit findings

Source: `performAccessibilityAudit` in the verify journeys, run 45825631128 (iPhone 17 Pro, light, dark, large text), on a main from before the text-style and 44 pt hit-area work. Lines are on main at 2924a6b. "Re-audit" means the finding cannot be tied to a line without a fresh run (`gh workflow run verify-ui.yml`, one at a time, main only). Fixed fonts: `git grep '.system(size:'` in App, Features, Design returns nothing now, so the old Dynamic Type "unsupported" findings are expected to be gone.

| # | Finding | File:line | Owner lane | Status |
|---|---|---|---|---|
| 1 | Home greeting, subtitle, chips, bubbles reported as fixed-size fonts | Features/Chat/ChatScreen.swift:157-174, Features/Presets/PresetViews.swift:37-38 | native-ux-research | likely fixed, re-audit |
| 2 | Preset chips clipped at AccessibilityXL (fixed chip width, one-line title and summary) | Features/Presets/PresetViews.swift:37-40 | native-ux-research | open |
| 3 | Picker rows truncate names and ids at AccessibilityXL ("AnyRo…", "Claude Sonn…") | Features/ModelPicker/ModelPickerSheet.swift:16-19, 49-58 | weekly-usage | open |
| 4 | Response-details row clipped, hit area too small | Features/Chat/MessageViews.swift:127-137 | chat-chrome | open |
| 5 | Copy and Regenerate hit area under 44 pt | Features/Chat/MarkdownTheme.swift:104-125, Features/Chat/MessageViews.swift:95 | chat-chrome | re-audit (frame now 44) |
| 6 | Sidebar thread titles and "Search chats" clipped at large text | Features/Threads/ThreadSidebar.swift:34, 81 | chat-search | fixed in 00e8805 (two lines at accessibility sizes), re-audit |
| 7 | Account name and email clipped; email read as "label not human-readable" | Features/Account/AccountCard.swift:56-58 | settings-ia | open |
| 8 | Contrast failed: home subtitle and chip text on the tinted wash | Features/Chat/ChatScreen.swift:168-174, Features/Presets/PresetViews.swift:37-38 | native-ux-research | re-audit |
| 9 | Contrast failed: "Manage models" title, "Search models" placeholder, picker "Model" title | Features/Hub/HubScreen.swift, Features/ModelPicker/ModelPickerSheet.swift | weekly-usage, settings-ia | re-audit |

## Open questions (operator)

- Q1 Add GitHub secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (API key role App Manager).
- Q2 Create the app record in App Store Connect (bundle id `dev.anyrouter.app`, name AnyRouter).
- Q6 Verify-later sign-up is a Clerk dashboard setting (email address, verify at sign-up), not code. Until it is off, new users are verified before the app gets its key and the Settings row never shows. The server also needs `/me` to return `email_verified` (duyet/anyrouter#8468, not merged). The app treats a missing field as verified.
- Q4 Resolved: icon from the public AnyRouter logo, anyrouter.dev orange accent (#8).
- Q7 "No cloud models" on a signed-in device (28bd02c). The public catalog decodes fine (510 entries checked against the decoder), so the cause is on the signed-in path and not proven without a key. What the code did: every engine error was dropped by `try?`, each partial answer replaced the whole list, and an empty list always read "No cloud models". Now the reason and Retry show, and Settings > Diagnostics keeps it. If it still happens, the Diagnostics row names the cause.
- Q5 Resolved: a sign-in token calls `tools/list` on `https://anyrouter.dev/api/v1/mcp` (initialize 200, 31 tools, no session id); no extra scope is needed.

## Native UX & performance

Audit of main at 00dee3c (2026-11-26). Every finding cites file:line on that commit. Nothing here was run on a device. Local checks were skipped (no Xcode on the maintainer Mac); numbers come from CI only, see § Measurement. Items marked "inference" are reasoned from the code and must be confirmed by the baseline (U1) before a fix claims a gain.

### Boundary (decision D15)

The reference design is a web app. "Match it 100%" cannot mean pixel-copying web widgets onto iOS. The boundary is:

- **Native containers and behavior:** NavigationSplitView, sheets with detents, List with selection, swipe actions and context menus, Form, .searchable, toolbars, iOS 26 Liquid Glass on the control layer, haptics, Dynamic Type, VoiceOver, hardware keyboard and pointer.
- **Reference tokens on top:** colors (ARColor), radii (10/14/24), spacing, type scale (mapped to text styles), brand accent, message bubble and markdown look, empty-state and onboarding content. Content surfaces (message bubbles, model cards) stay flat in token colors. Glass is for navigation and controls only.

| Screen | Native container | Reference tokens kept | Deviation from the reference, and why |
|---|---|---|---|
| Shell | NavigationSplitView: sidebar + chat on iPad, list then chat on iPhone, opens on the chat (preferredCompactColumn = detail) | sidebar width 300, sidebar fill | iPhone drawer over the chat becomes the system push. We get edge-swipe back, interactive transition, iPad sidebar toggle, Stage Manager resizing, restoration. The drawer cannot give any of these. |
| Chat | Navigation bar with toolbar items (menu or back, model pill as principal item, new chat) | message bubble color, radius 18, markdown theme, empty state | Opaque bordered circles become system glass buttons. Same icons, same positions. |
| Composer | safeAreaInset bottom bar | radius 24, plus and send buttons, placeholder | Fill is Liquid Glass instead of an opaque bordered card, so messages scroll under it. Geometry is unchanged. |
| Thread list | List(selection:) with swipe actions, context menus, .searchable | row text, pinned section, accent | System selection and hover replace the custom pill; row fill still uses sidebarAccent. Search field is the system one. |
| Model picker | Sheet (medium, large detents) with NavigationStack, List, .searchable | grouping, subtitles, accent check | Bordered card rows become list rows. Sheet background is no longer opaque, so glass shows at the medium detent. |
| Hub | Pushed or sheet page in a NavigationStack with .searchable and .refreshable | ModelCard (bordered card, chips, fit badge) | Page header and search field become system ones. Cards stay because they are content. |
| Settings | Sheet with Form (grouped) | labels, accent, slider tint | Bordered card groups become grouped Form sections (Dynamic Type reflow, footers, keyboard navigation for free). |
| Onboarding | Full-screen cover (unchanged) | everything | None. |
| Type | Text styles with a documented map, @ScaledMetric for icon frames | scale: XS 12, SM 14, Base 16, LG 18, XL 20, Title 24, Hero 30 | Mapped to caption, subheadline, callout, body, title3, title2, title. Each size moves by at most 2 pt at the default setting. The price of scaling. |

### Findings

**Navigation**

- N1 Custom drawer and HStack instead of a split view: Features/Shell/AppShell.swift:11-47. The drawer only closes by drag (:39-43), never opens by edge swipe, with a fixed 0.22 s animation (:49).
- N2 A size-class change resets the sidebar (AppShell.swift:50-52), so Split View or Stage Manager resizing flips it.
- N3 Hub and Settings are routes swapped inside the detail (AppShell.swift:61-65) with a custom back circle (Design/ARComponents.swift:131-146). No swipe-back, no transition, back always lands on chat. The picker dismisses then switches route (Features/ModelPicker/ModelPickerSheet.swift:100-103).
- N4 No restoration: selectedThreadID is nil on every launch (Features/Shell/ShellModel.swift:11); no SceneStorage anywhere.
- N5 No onOpenURL, no App Intents, no Spotlight. OAuth uses the loopback callback, so no URL scheme exists today.
- N6 No hardware keyboard support: no keyboardShortcut or Commands. Return inserts a newline (Features/Chat/Composer.swift:21). The FocusState is declared but never driven (:7, :20), so a new chat does not focus the composer.
- N7 No pointer or keyboard focus on custom controls: .buttonStyle(.plain) over a custom background (ARComponents.swift:30); thread rows use onTapGesture (Features/Threads/ThreadSidebar.swift:96), so they are not buttons for VoiceOver either.
- N8 Multi-window: shell state is per window (App/RootView.swift:6) and AppState is shared, which is the right split. Whether the scene manifest allows multiple scenes is unverified (project.yml:78 only generates it). Check on an iPad.

**Native feel**

- F1 The top bar is views in a VStack (Features/Chat/ChatScreen.swift:30-40) with opaque card circles (ARComponents.swift:17-34): no toolbar, no glass, no scroll-edge effect.
- F2 The composer is an opaque card in a VStack (Composer.swift:39, Design/ARTheme.swift:29-32), not a bottom inset, so messages never scroll under it.
- F3 The picker forces an opaque background (ModelPickerSheet.swift:47), which hides the iOS 26 sheet glass at the medium detent. It is a ScrollView of bordered cards, not a List (:29-45).
- F4 Settings is a ScrollView of bordered groups (Features/Settings/SettingsScreen.swift:24-37, :153-171). No Form semantics. Section titles lack the header trait (ARComponents.swift:117-128).
- F5 Three custom search fields (ARComponents.swift:88-113; ThreadSidebar.swift:25, HubScreen.swift:27, ModelPickerSheet.swift:26): no system focus or cancel, no find shortcut. The only boundary is a 1.3:1 border in light mode.
- F6 Dynamic Type is broken: 26 fixed-size font sites (ARTheme.swift:18-24 plus 19 inline), the comment at ARTheme.swift:17 claims the opposite, MarkdownUI is pinned to FontSize(16) (Features/Chat/MarkdownTheme.swift:11), and controls are fixed 40 pt (ARTheme.swift:12).
- F7 No haptics anywhere.
- F8 Accessibility gaps: hit targets of 28-32 pt (MarkdownTheme.swift:119, Features/Chat/MessageViews.swift:50, Composer.swift:27, :53, :61); the model pill reads "Model" without its value (Features/ModelPicker/ModelPill.swift:23); TypingDots ignores Reduce Motion (MessageViews.swift:73); no announcement when a reply finishes; copy and regenerate are not accessibility actions.
- F9 Good: color tokens are dynamic light and dark (ARColor.swift:26-30); swipe actions and context menus exist (ThreadSidebar.swift:100-116); the scroll dismisses the keyboard interactively (ChatScreen.swift:107).

**Performance**

- P1 One SwiftData mutation per token on the main actor: assistant.content += piece (Features/Chat/ChatViewModel.swift:112). Each one is a change plus an Observation invalidation (inference: autosave work too).
- P2 The list body re-runs per token because onChange(of: messages.last?.content.count) is evaluated in body (ChatScreen.swift:110). messages sorts the whole relationship on every access (ChatViewModel.swift:33-35), called again by canRegenerate (:44-46). O(n log n) per token at n = 200.
- P3 MessageRow cannot be skipped: it takes a reference model and a fresh closure per body (ChatScreen.swift:93-98, MessageViews.swift:5-9). Every realized row rebuilds the Theme (MarkdownTheme.swift:7, MessageViews.swift:39) and recreates Markdown(message.content) (MessageViews.swift:38). Measured (baseline): the row body takes about 60 microseconds, so building the view is not the cost. The app burns about one full core for the whole 1,000-token stream, so the cost sits in the MarkdownUI subtree (parse and layout of the whole reply on each update), which the row.assistant signpost cannot see.
- P4 scrollTo("bottom") on every content change (ChatScreen.swift:109-112): forces layout per token and drags the reader down while they read earlier text. No jump-to-latest control.
- P5 The reply is saved only at the end (ChatViewModel.swift:125-136). Killing the app mid-reply loses it.
- P6 The model list waits for the slowest engine: allModels awaits each engine in turn (Core/EngineRegistry.swift:15-22) and the cloud request uses the default 60 s timeout (Engines/AnyRouter/AnyRouterEngine.swift:32-34). Until it returns, selected is nil (Features/ModelPicker/ModelStore.swift:23-26), the composer says "Choose a model to start" (Composer.swift:15) and send is refused (ChatViewModel.swift:55-58). On a bad network Apple and local models are unusable for up to a minute. There is no cached list. hub.reload then models.refresh also run in series (RootView.swift:27-30).
- P7 Before the first frame: ModelContainer opens synchronously (App/AnyRouterApp.swift:12); AppState builds four engines (App/AppState.swift:14-22), AnyRouterAuth reads the Keychain three times (Engines/AnyRouter/Auth/AnyRouterAuth.swift:23, :33; KeychainStore.swift:15-23), LocalModelHub creates the background URLSession (AppState.swift:12; Engines/Local/Downloads/ModelDownloadManager.swift:33-38). After it, hub.reload does file IO on the main actor (ModelDownloadManager.swift:61-65, :143). Constraint: the session must exist when the system relaunches us for background events (App/AppDelegate.swift:8-12), so defer it, do not remove it. Cost unknown until U1.
- P8 Picker: sections are filtered, sorted and formatted twice per body (ModelPickerSheet.swift:13-15, :31, :38; Features/ModelPicker/ModelPickerLogic.swift:24-40, :50) inside an eager VStack (:30). 500 models means 500 rows built at open. No search debounce.
- P9 Hub: eager VStack (Features/Hub/HubScreen.swift:29-30); installedIDs asks the state of every catalog entry each body (:19-21, :44); a progress tick re-renders the whole screen.
- P10 Thread search checks every message of every thread on the main actor per keystroke (Features/Threads/ThreadListLogic.swift:20-24), faulting all messages, with no debounce (ThreadSidebar.swift:18-20).
- P11 Memory: unload() exists on both local engines (Engines/Local/GGUF/GGUFEngine.swift:62, Engines/Local/MLX/MLXEngine.swift:53) and nothing calls it. Weights stay resident after the chat, with no memory-warning or background release. The increased-memory-limit entitlement raises the ceiling, not the pressure. First send on a local model shows typing dots for the whole load (GGUFEngine.swift:10, MessageViews.swift:34-36).
- P12 Cloud SSE reads one byte per await (AnyRouterEngine.swift:76-83). Known CPU cost, fine at chat rates; leave until a baseline says otherwise. Note that bytes.lines drops the blank lines SSE uses as separators.
- P13 Images and logos: only a bundled template asset (ARComponents.swift:8), no AsyncImage. Nothing to cache yet; add a cached loader when provider logos arrive.
- P14 Good: generation and model load run off the main actor (GGUFEngine.swift:10, :69; MLXEngine.swift:60); the chat list is a LazyVStack (ChatScreen.swift:91); catalog work is in an actor.

### Measurement (Explain the Number)

All numbers are Simulator numbers from a shared macOS runner. They rank changes against the previous baseline from the same job. They are not device numbers: the Simulator has no thermal limit and a different GPU path, so hitch ratios are low confidence and CPU time is the main signal. Device checks (Instruments, MetricKit) stay manual until F1.

| ID | Metric | How CI measures it | Caveat | Target (proposal) |
|---|---|---|---|---|
| M1 | Cold launch | XCTApplicationLaunchMetric(waitUntilResponsive: true), 5 iterations, Release build, after a discarded warm-up; signposts split out container, engines, auth, hub | Simulator process start and the XCUITest responsiveness wait dominate. Not the system-measured launch on device | Our signposts are about 6% of it, so no target on the total; device first frame under about 400 ms (Apple guidance) |
| M2 | Chat scroll | XCTCPUMetric (app CPU time) for 4 fast swipes down and 4 up on a 200-message thread (-ARDemoLongThread 200). XCTHitchMetric was tried: it reports nothing on the Simulator | CPU time, not frame pacing. Includes gesture handling | CPU time down after U3 to U6; device hitch ratio under 5 ms/s (Apple "good"), measured by hand |
| M3 | Streaming cost | Demo engine, 1,000 tokens at 50 tok/s (about 23 s with typing), new chat per iteration. XCTCPUMetric and XCTMemoryMetric around the whole block, minus an idle control of 20 s; signpost row.assistant (row body time, MarkdownUI subtree excluded) | CPU is the whole app process, so engine cost is zero here (fake engine) and render cost is included. Manual start and stop made XCTCPUMetric fail on the Simulator, so the typing seconds are in the block | -50% CPU per stream after U3 and U5, from the baseline below |
| M4 | Picker open | -ARDemoManyModels 500; XCTClockMetric and CPU from the tap until the first row is on screen, plus closing the sheet, with a 6-model control (no in-app signpost, to keep the Features files free) | The block includes XCUITest reading the screen, which grows with the row count. The control separates it | 500 models within 2x of the 6-model control after U9 |
| M5 | First usable model | -ARDemoCloudDelay 5; signpost models.firstUsable from ModelStore init | Shows the P6 bug directly: baseline is the 5 s delay plus about 1.5 s to the first body | under 2 s after U7, independent of the delay |

Noise rule: run the perf class 3 times (3 separate xcodebuild invocations, 5 iterations each). Report per run average and relative standard deviation, plus the spread of the three run averages. A change counts only when it moves the mean by more than twice the spread across runs. No gate until we have a few baselines.

### Baseline (U1, 2026-11-26)

CI run [45806661476](https://github.com/AnyRouterHQ/AnyRouterApp/actions/runs/45806661476) on main at c69fd83 plus the U1 changes (main has moved since; the run after U1 merges is the next data point), iPhone Simulator (macOS runner), Release build, one discarded warm-up, then three runs. Means of the three run averages, with the spread across the run averages (max minus min over the mean). Raw lines and JSON are in the run's `perf` artifact.

| Metric | Mean of runs | Run averages | Spread | Reading |
|---|---|---|---|---|
| M1 cold launch to responsive | 4.37 s | 4.99, 4.05, 4.08 | 21% | Run 1 is slower every time (first run on a fresh Simulator). Our own code is small, see below |
| launch.container (SwiftData open) | 0.10 s | 0.12, 0.10, 0.08 | 35% | |
| launch.engines | 0.012 s | 0.020, 0.008, 0.007 | 110% | |
| launch.auth (Keychain) | 0.059 s | 0.110, 0.025, 0.041 | 145% | One cold iteration reached 0.66 s in an earlier run |
| launch.hub (background URLSession) | 0.11 s | 0.25, 0.054, 0.030 | 199% | Same cold-first pattern |
| M5 models.firstUsable, cloud list delayed 5 s | 8.0 s | 10, 7.2, 6.7 | 44% | Runs 2 and 3 agree: 5 s delay plus about 1.5 s. Apple and local models were usable at launch but stayed unusable until the slow list returned (P6) |
| M3 stream, app CPU over about 23 s | 24.6 s | 24.5, 26.1, 23.3 | 11% | Idle control over 20 s: 0.004 s. One full core is busy for the whole stream |
| M3 stream, peak memory | 89 MB | 90.3, 89.1, 87.8 | 3% | Idle control 57 MB |
| M3 row.assistant body time | 63 microseconds | 71, 15, 103 | 139% | Tiny and noisy. Building the row is not the cost (P3) |
| M4 picker with 500 models, tap to first row | 12.0 s clock, 9.1 s CPU | clock 13.5, 12.3, 10 | 26% | 6-model control: 4.1 s clock, 0.79 s CPU. The list itself adds about 8 s of app CPU |
| M2 scroll, app CPU for 8 fast swipes | 4.1 s | 3.3, 6.0, 2.8 | 78% | Too noisy to rank anything under about 2x. Needs more iterations or a quieter runner before it can judge U3 to U6 |

Run 2 (CI run [45866770646](https://github.com/AnyRouterHQ/AnyRouterApp/actions/runs/45866770646), main at a435eff, same method). Main had moved a lot between the runs, so these are not single-change comparisons.

| Metric | Run 1 mean | Run 2 mean | Run 2 averages | Reading |
|---|---|---|---|---|
| M5 models.firstUsable, cloud list delayed 5 s | 8.0 s | 2.37 s | 2.27, 2.51, 2.32 | U7 works: Apple and local models no longer wait for the slow list. Spread 10% |
| launch.auth (Keychain) | 0.059 s | 0.0003 s | | U8 by the diagnostics lane |
| launch.engines | 0.012 s | 0.0005 s | | same |
| launch.container, launch.hub | 0.10 s, 0.11 s | 0.11 s, 0.06 s | | unchanged within noise |
| M1 cold launch to responsive | 4.37 s | 8.36 s | 12.9, 6.5, 5.6 | Slower; run 1 is again the outlier. Not from our four signposts (all small); other launch work was added meanwhile (watchdog, diagnostics store). Needs its own look |
| M2 scroll, app CPU | 4.1 s | 10.09 s | 9.97, 10.12, 10.17 | More than doubled, spread 2%, so it is real. Suspect: the `ScrollPosition` binding I added in 8ee3458 is written every scroll frame and re-evaluates the list. Replaced by `ScrollViewReader` in 42cdb1f; unverified until the next run |
| Idle control, app CPU over 20 s | 0.004 s | 0.052 s | | Small, but 13 times higher. Cause found in code: the main-thread watchdog ran a 50 ms timer on the main thread plus a 50 ms loop on a second thread forever (40 wake-ups a second), and the memory readout refreshed every 3 s on the home screen. Both are event-driven now; confirm with the next run |
| Idle memory | 57 MB | 73 MB | | More code and services at launch |
| M3 stream, M4 picker | | not measured | | The perf tests no longer matched the UI (tabbed picker, two "New chat" buttons); fixed in 42cdb1f |

What this changes:

- Streaming is the biggest problem: one core for the whole reply on the Simulator. U3, U4 and U5 stay first. U4 is demoted to a follow-up because row bodies are cheap.
- Launch is mostly the Simulator and XCUITest. Our four signposts add up to about 0.3 s of 4.4 s, so U8 leaves the top 10.
- P6 is real and reproducible: usable local models wait for the slowest cloud call. U7 is a cheap, certain win.
- The 500-model picker is slow in the app, not only in the test: 8 s more CPU than the control. U9 stays.
- Not measured: hitches (no output on the Simulator), device numbers, iPad. Spread over 50% means the number cannot rank changes yet.

### Checklist (small PRs, in this order)

Size S under 1 day, M 1-3 days, L more. "After" names open work in the same files; rebase on it, do not edit it.

- [x] U1 (ebe6ee6) Perf baseline (numbers in § Baseline): signposts (launch.container, launch.engines, launch.auth, launch.hub, models.firstUsable, row.assistant), PerformanceTests in the UI test target, demo flags (-ARDemoLongThread, -ARDemoManyModels, -ARDemoStream, -ARDemoCloudDelay), `perf.yml` job summary with 3 runs. Baseline only.
- [x] U2 (12321d4, with the Settings and Hub lanes; no fixed-size font is left) Dynamic Type: map ARTheme tokens to text styles (ARTheme.swift:18-24), replace the 19 inline sizes, @ScaledMetric for icon frames and controlSize, scaled MarkdownUI size via a cached theme. Fix the comment at ARTheme.swift:17. Effect: text follows the system size, including accessibility sizes. Metric: UI test at the largest accessibility size on all screens, no truncated primary control; the accessibility audit reports no Dynamic Type issues.
- [ ] U3 (M, after #24, #28) Streaming path: keep streaming text in the view model and flush at most 30 Hz; write the record on finish and every 2 s as a checkpoint (P1, P5); stop reading content in the list body (P2). Effect: smooth typing, no lost replies. Metric: M3. Done so far: a 20 Hz `TextCoalescer` (another lane) and the deleted-thread guard (8ee3458). Open: checkpoint writes and keeping the text off the record; re-measure before doing them.
- [ ] U4 (S, after U3) Row identity: Equatable MessageRowModel value, actions through the environment, one cached Theme, ordered array kept in the view model instead of sorting per access (P2, P3). Effect: finished rows never re-render during a stream. Row bodies are cheap (P3), so the gain is skipping their subtree work; do it after U3 and judge it by M3 CPU, with 0 body updates for non-streaming rows (debug counter). Blocks (U5) removed most of the cost; do this only if the next baseline still shows row work.
- [x] U5 (8ee3458: `MarkdownBlocks` splits at blank lines outside fences, equatable blocks, the live tail is Markdown too, not plain Text) (M, after U4) Stable-prefix markdown: render completed blocks with Markdown and the live tail as plain Text (break at the last blank line outside a code fence). Effect: no reflow jump at the end, flat per-token cost. Metric: M3 row.assistant per reply flat instead of growing.
- [x] U6 (8ee3458: `ScrollFollow`, `onScrollPhaseChange`, jump-to-latest button) (S, after U3) Scroll follow: pinned-to-bottom state from onScrollGeometryChange, scroll only when pinned, jump-to-latest button, defaultScrollAnchor(.bottom, for: .sizeChanges) instead of per-token scrollTo (P4). Effect: you can read while it streams. Metric: M2 and a UI test that scrolls up during a stream and stays put.
- [x] U7 (see the commit that adds EngineRegistry.modelListings; the cloud request already had a 15 s timeout; no disk cache yet) Model list: per-engine tasks with incremental publish, 8 s timeout on the cloud request, last list cached on disk, hub.reload and models.refresh in parallel (P6). Effect: Apple and local models usable at once, offline or on a bad network. Metric: M5. Check the `fix/anyrouter-default-model` branch first, it may touch the same store. Exact changes sent to the picker lane, which owns ModelStore.
- [x] U8 (25dc199, diagnostics lane: Keychain and Sentry off the launch path) (M, after U1) Launch path: container, Keychain reads, URLSession creation and hub.reload off the first-frame path; create the background session in the delegate callback too (P7). Effect: only the cold Keychain and session outliers (first iteration up to 0.7 s) go away; the rest is under 0.3 s of a 4 s Simulator launch (§ Baseline). Low priority. Metric: M1 signposts.
- [ ] U9 (S) Picker and Hub lists: lazy containers, sections cached in ModelStore, one ByteCountFormatter, 150 ms search debounce, per-card progress observation so a tick redraws one card (P8, P9). Effect: instant open with hundreds of models. Metric: M4.
- [x] U10a (L, after #23, #28) Shell: NavigationSplitView, sidebar List(selection:) with Button rows, toolbar items, ShellModel.sheet for settings, hub and picker, SceneStorage for the selected thread, UITests selectors updated in the same PR (N1-N4, N7). Effect: edge-swipe back, iPad sidebar toggle, state restored after relaunch. Metric: UI tests for swipe-back and relaunch restore; navigation transition hitches via XCTOSSignpostMetric.navigationTransitionMetric. Done in b8cbfb1, e7589eb: iPhone keeps the drawer (D19), toolbar top bar, SceneStorage restore, hub is a sheet. Left: UI test selectors, List(selection:) sidebar rows, ShellModel.sheet enum.
- [x] U10b (S, after U10a) Settings as Form in a sheet (F4). U10c (S, after U10a) Hub as sheet with .searchable and .refreshable (F5). U10d (S, after U10a) Picker as List with .searchable and its own NavigationStack so "Browse more models" pushes (F3, N3). Done in d4a5990 (grouped List in a sheet, not Form) and e7589eb (hub sheet with searchable and refreshable).
- [x] U11 (M, after U10a) Liquid Glass: glass composer in a safeAreaInset with GlassEffectContainer and glass buttons, scrollEdgeEffectStyle under it, no opaque sheet backgrounds (F1-F3). Effect: native iOS 26 look. Metric: M2 before and after (glass over scrolling content must not add hitches); Reduce Transparency screenshot check. Done in b8cbfb1: glass toolbar controls, model pill, composer in a safeAreaInset, scroll edge effect, Reduce Transparency fallback (ARGlass). Left: ModelPickerSheet opaque background (picker lane file), M2 number.
- [ ] U12 (S) Haptics with sensoryFeedback: send, stop, model change, pin, copy, download finished, error. Not per token. Effect: tactile feedback. Metric: manual on device, Simulator has no haptics. Done so far: light impact when a send starts, success on copy (d1568ed).
- [x] U13 (M, after U10a) Keyboard and pointer: Commands for new chat (cmd N), model menu (cmd K), search (cmd F), settings (cmd comma) routed by FocusedValue per window; Return sends and Shift-Return adds a line on hardware keyboards; focus the composer on new chat; hover effects; verify multiple windows on iPad (N6-N8). Metric: UI test with typeKey for each shortcut. Done in e7589eb except pointer hover effects and multi-window check: Cmd N, K, F, comma via FocusedValue; Return sends, Shift-Return adds a line.
- [x] U20 (62e30d3) iPad and iPad mini layout (D21): automatic sidebar column 280/320/400, readable 720pt chat column, popover model picker, form and page sheets, hover highlights on plain and borderless buttons, `UITests/PadLayoutTests` and `ipad-ui.yml` (iPad mini and iPad Pro 13, dispatch by hand). Left: iPad mini in `screenshots.yml` (screenshots lane), a draft is lost when a Stage Manager resize flips between regular and compact (the chat view model is rebuilt).
- [ ] U14 (M) Accessibility: 44 pt hit areas, copy and regenerate as accessibility actions, model pill value, header traits, Reduce Motion for TypingDots, announcement when a reply ends, XCUIApplication.performAccessibilityAudit in a UI test (F8). Metric: audit reports 0 issues on the main screens. Done so far: 44 pt hit areas and text styles in chat, composer, presets (12321d4). The audit tests are the coverage lane's.
- [ ] U15 (S) Thread search: predicate-based fetch (localizedStandardContains on title and messages) with a 200 ms debounce (P10). Metric: keystroke to results on 200 threads; ask lane A before any Core index change.
- [x] U16 (memory-warning unload by lane C; unload after 5 minutes in the background d1568ed) Memory: call unload() on memory warning and after the app has been in the background for a few minutes; show "Loading model" while a local engine loads (P11). Metric: M3 memory after the stream and after backgrounding.
- [ ] U17 (L, low) Deep links, App Intents (new chat, ask), opt-in Spotlight of chat titles (N5). Chat titles are private, so Spotlight is off by default.
- [ ] U18 (S, only if M3 on the real SSE path shows it) Chunked SSE read instead of per-byte (P12), with the blank-line rule kept.

Top 10 for the next lanes, by user-visible effect per day of work: U1 (done), U3 with U4, U7, U10a, U2, U11, U13, U6, U9, U5. U8 dropped out after the baseline.

### UX audit against Apple's HIG (U19 to U27)

Read for this audit: HIG [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility); WWDC25 [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/), [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/), [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/). The rules we hold the app to: glass belongs to the navigation and control layer, never to content, and never on top of other glass; system components adopt glass by themselves; a control has at least a 44 by 44 pt hit region; text uses text styles; color comes from semantic colors and one tint. Screenshots checked: the three operator device screenshots (drawer over the home screen, Settings, Theme). Ranked by user impact. "Mine" means done in files the native lane owns.

- [x] U19 (d1568ed, mine) Toolbar items carried a per-item `.tint(.primary)` (Features/Chat/ChatScreen.swift toolbar, two buttons). The accent is mono, so the override only hid the system look. [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars). Removed.
- [ ] U20 (shell lane) The home background paints an accent gradient at the top (Design/ARHomeBackground.swift:15-22). In the mono theme it reads as a grey smear behind the glass controls (operator screenshot of the drawer and home screen). [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Color](https://developer.apple.com/design/human-interface-guidelines/color). Fix: delete `ARHomeBackground` and use `Color(.systemBackground)`; let the composer glass and the scroll edge effect carry the depth.
- [ ] U21 (shell lane) The sign-in card shows the server's own words, "The database is briefly unavailable. Retry in a few seconds." (Features/Account/AccountCard.swift:37, :72). [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), HIG Writing. Fix: map known failures to one plain line, keep the raw text in Diagnostics.
- [x] U22 (23a062d, mine) The model pill was a `.glass` button inside the principal toolbar item. Replaced by `ModelTitle`, a plain button with the toolbar background hidden, so there is no glass on glass. [Materials](https://developer.apple.com/design/human-interface-guidelines/materials).
- [ ] U23 (coverage lane, tests) Contrast: `.secondary` text is about 3.4 to 1 on white, and the HIG asks 4.5 to 1 for text under 18 pt. Status and error text must use `.primary` or a status color; `.secondary` stays for captions only. [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility). Check: `performAccessibilityAudit(for: .contrast)` on home, chat, picker, Settings, light and dark.
- [ ] U24 (hub lane) The Hub "Pause" button is tinted orange (Features/Hub/HubScreen.swift:259). Orange is for the "tight fit" status only (Features/Hub/ModelRow.swift:9, :20); a button takes the app tint. [Color](https://developer.apple.com/design/human-interface-guidelines/color).
- [ ] U25 (coverage lane, tests) Dynamic Type at the largest accessibility size: launch with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and run `performAccessibilityAudit(for: [.dynamicType, .textClipped, .hitRegion])` on home, chat, picker, Settings. [Typography](https://developer.apple.com/design/human-interface-guidelines/typography).
- [x] U26 (12321d4, mine) Hit regions: the composer's send, stop and presets buttons, regenerate and copy were 28 to 36 pt. Now 44 pt or more: glass and bordered-prominent circle buttons with `.controlSize(.large)`, `.frame(minWidth: 44, minHeight: 44)` on borderless ones. [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- [x] U28 (23a062d, mine) Chat chrome: two system glass toolbar buttons around a plain bold model title with a chevron; composer in `safeAreaBar` so the system scroll edge effect blurs content under both bars; one 44 pt `.glassProminent` round button in the field (voice, send, stop); presets and the memory readout moved into the plus menu. Voice only raises the keyboard until M4 dictation lands. [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).
- [x] U29 (5b7a61a) Search chats: the sidebar row is a button that opens `ThreadSearchScreen` (full-screen cover on iPhone, page sheet on iPad) with the system search field focused on appear, every chat, newest first, when blank, title and message matches with a snippet otherwise; accent- and case-insensitive incl. Vietnamese đ (`ThreadSearchLogic`). The inline sidebar search and the drawer keyboard resize rule are gone; swipe and context actions are shared in `ThreadRowEditing`. Not built: the trailing unread dot (no unread state exists) and a per-type icon (pin or bubble only).
- [x] U30 (00e8805) Sidebar redesign: plain list on the system background with an "AnyRouter" title row and the logo mark, a Search chats row, Pinned and Recents (10, with View all opening the search with every chat), a More section (Decisions, `sidebar-decisions`), and a pinned bottom bar with a round glass Settings (gear) button and a capsule New chat; Search chats is a quiet 36 pt capsule row. The chat beside the open drawer is no longer dimmed: the dim overlay is now a clear tap target and the gradient edge is a 0.5 pt separator along the concentric corners. Rows paint their own highlight for the open chat and allow two lines at accessibility sizes (audit finding 6). Not built: the trailing unread dot (no unread state; it needs a field in `ThreadRecord`, a Core change) and a per-kind icon (every chat uses the bubble).
- [x] U27 (mine) Preset chips were a fixed 190 pt wide (Features/Presets/PresetViews.swift) and truncated at large text sizes. The width is now a `@ScaledMetric`. [Typography](https://developer.apple.com/design/human-interface-guidelines/typography).

Subtract list, done (12321d4, d1568ed): deleted `ARChip`, `ARIconButton`, `ARSearchField`, `ARButtonStyle` (`.arFilled` and friends), `ARComingSoon`, `ARGlass`, the `.ar*` fonts and `ARColor`; `CodeBlockView`, `CopyButton`, `ErrorBanner` and `TypingDots` now use stock components (symbol effect, system close button); presets are a `List` in a `NavigationStack` with `.searchable` and a filter menu, and a `Form` in Settings. The native ratchet is at 1 (the composer's tap-to-focus gesture, with its reason in a comment).

Not doing: a custom navigation container, per-token haptics, pull-to-refresh on the thread list (local data, nothing to refresh), UIKit views, replacing MarkdownUI before U5 is measured.

## Review findings

Reviewer passes over main up to 8e275cd (2026-11-27). Fixed items are in `fix(...)` commits; the lines below were left for the owning lane. One line each; delete a line when it is done.

- Features/Settings/AppSettings.swift:81 and Core/Telemetry.swift:130 — diagnostics sharing is on by default whenever a DSN is built in, so a release with a DSN reports without the user opting in. For a privacy-first open source chat app, default it off and ask once (onboarding or Settings). Operator decision.
- Core/ChatAttachment.swift:6 — the synthesized `Decodable` needs every non-optional key (`isOCR`, `isTruncated`); the next field added makes old rows fail `try?` in `MessageRecord.attachments` and their attachments vanish. Add `init(from:)` with `decodeIfPresent` defaults before any change. Same for `ToolStep`, `ToolCall`, `ToolResult`. Owner: lane D (attachments).
- Features/Chat/ChatViewModel.swift:200 — `try? attachmentStore.adopt` drops an attachment that failed to move, and the message is sent without it and without a notice. Report it. Owner: lane D.
- Core/Records.swift:75 — `attachments`, `metadata` and `toolSteps` decode JSON on every access, and rows read them on every render. Decode once per row or cache. Owner: perf lane.
- App/AnyRouterApp.swift:16 and Core/Records.swift — `fatalError` when the store fails to open and no `VersionedSchema` or migration plan exists; the new optional fields migrate on their own, but the first rename or required field bricks launch. Add a versioned schema, or move the store aside and start empty with a notice. Owner: lane A.
- Engines/AnyRouter/AnyRouterEngine.swift:146 — the stream loop reads one byte at a time from `AsyncBytes` and splits lines again before `SSEParser`; read bigger chunks. Same in MCPClient.read and FetchURLTool. Owner: lane B.
- Engines/AnyRouter/Auth/LoopbackCallback.swift:68 — accepted connections are not tracked or timed out and survive `stop()`. Low risk (state check gates delivery). Owner: lane B.
- Features/ModelPicker/ModelPickerSheet.swift:312 — the list is refreshed on sign-in only; a download that finishes while the Hub is closed shows up after the next refresh. Refresh on open. Owner: lane D (picker).
- .github/workflows/device-ipa.yml:5 — a second full macOS device build runs on every push to main next to `ci.yml` (macOS minutes cost 10x); build the IPA on `workflow_dispatch` or nightly. Owner: lane A (CI).
- Not reviewed in depth: Hub families and filters UI, the picker and Decisions screens, onboarding, the drawer shell, screenshot and perf tests.

## Status log

- 2026-11-27 lane-verify: accessibility audit findings table with owners (run 45825631128); screenshots.yml split into build plus per-device shards; local checks skipped

- 2026-11-26 lane-ux: native UX and performance audit, boundary decision D15, plan U1-U18 and measurement plan; docs only, local checks skipped
- 2026-11-26 lane-mcp: MCP client, typed tool models, Settings › Integrations with per-tool switches (T1-T2) (#33); local checks skipped

- 2026-11-26 lane-ui: launch screen shows the logo on a themed background, AppIcon dark and tinted variants, asset test; local checks skipped
- 2026-11-26 lane-docs: local inference roadmap (L1-L10 verdicts, shared Core shapes, PR sequence S1-S9), decision D14; docs only, local checks skipped
- 2026-11-26 lane-ci: unsigned debug IPA workflow `device-ipa.yml` and `docs/sideload.md`; local checks skipped
- 2026-11-26 lane-F8a: demo data mode, UI screenshot tests, screenshots workflow (#23); local checks skipped
- 2026-11-26 lane-C: Gemma 4 E2B/E4B in the catalog (GGUF + MLX), Gemma 4 prompt format, model-smoke `model_id` input (F10, #25); llama.cpp stays at b10456, mlx-swift-lm at 3.33.0; local checks skipped
- 2026-11-26 lane-docs: rewrite README for users; contributor detail already in AGENTS.md (#17); local checks skipped

- 2026-11-26 lane-F9: model-smoke workflow and Tests/Integration (GGUF real-model, installer, download manager, Apple availability); local checks skipped
- 2026-11-26 manager: lanes A-D done (#1-#14), backlog F1-F8 added, lane E started (workflow gated on signing secrets).

- 2026-11-26 manager: interviewed operator, wrote AGENTS.md + PLAN.md + base config, created public repo AnyRouterHQ/AnyRouterApp, started lanes A, B, C.
- 2026-11-26 lane-A: scaffold, Core contract, app shell, CI workflow (#1); local checks skipped
- 2026-11-26 lane-D: design tokens, adaptive shell, threads sidebar, AnyRouter icon (#8); local checks skipped
- 2026-11-26 lane-D: chat screen, composer, markdown (MarkdownUI), view model tests (#9); AppState now registers the Apple and AnyRouter engines; local checks skipped
- 2026-11-26 lane-D: model picker, hub, `LocalModelHub` adapter, background session app delegate (#12); local checks skipped
- 2026-11-26 lane-D: settings, onboarding, licenses (#13); lane D tasks D1-D7 done; local checks skipped
- 2026-11-26 lane-D: engine wiring: GGUF and MLX registered, increased-memory-limit entitlement, MLX unavailable reason in the hub; restore and background session handler already wired in #12 (#14); local checks skipped
- 2026-11-26 lane-A: hygiene (gitleaks, dependabot, templates, README, notices) (#3); PR #1 merged, CI green
- 2026-11-26 lane-B: Apple + AnyRouter engines, OAuth sign-in, SSE/PKCE tests (#2); local checks skipped, CI is the gate
- 2026-11-26 lane-C: catalog, HF client, device fit, background downloads and installer with tests (#7); local checks skipped
- 2026-11-26 lane-C: GGUF engine on llama.cpp b10456 with a real tiny-model test (#10); local checks skipped
- 2026-11-26 lane-C: MLX engine on mlx-swift-lm 3.33 with Simulator guard (#11); generation path to be verified on device; local checks skipped
- 2026-11-26 lane-E: ad-hoc release workflow, signing scripts, install doc (E1-E2); signing path untested until secrets exist; local checks skipped
- 2026-11-26 chore: neutral references, reference notes moved to gitignored AGENTS.local.md, CI check for banned names; local checks skipped
- 2026-11-26 lane-E: switched milestone 1 from ad-hoc to TestFlight: `testflight.yml`, `docs/testflight.md`, ITSAppUsesNonExemptEncryption=NO in project.yml (E1-E2); local checks skipped
- 2026-11-26 lane-F15: prompt presets (empty-chat starters, composer sheet, custom presets in Settings) (#28); local checks skipped
- 2026-11-26 lane-F16: home screen redesign, composer layout, thinking flag per thread (#36); engine wiring pending (F17); local checks skipped
