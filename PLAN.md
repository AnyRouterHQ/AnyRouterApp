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
| D10 | Persistence: SwiftData for threads/messages; Keychain for the AnyRouter key; `UserDefaults` for settings | Simplest native stack. |
| D14 | No custom llama.cpp fork in v1.x. GGUF features that need more than `libllama` (speculative decoding, TurboQuant KV) wait for F4: our own xcframework built from an official tag. A fork is considered only if a measured on-device need remains after F4. | The official tags already carry MTP, DFlash and EAGLE-3 in `common/`. Forks add upkeep and licence review, and the app ships weights, not new engines. |
| D12 | llama.cpp is pinned to release b10456 through a local package `Packages/LlamaBinary` (binaryTarget + checksum) | b10456 is the newest official xcframework with iOS Simulator and device slices. From b10488 on, releases ship device slices only, and CI builds for Simulator. Revisit when upstream restores the simulator slice. |

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

### Lane C — local Hugging Face models (model: sonnet-high)
- [x] C1 `Engines/Local/Catalog`: bundled `catalog.json` (curated small models that fit phones: e.g. Qwen3 0.6B/1.7B/4B, Gemma 3 1B/4B, Llama 3.2 1B/3B, in GGUF Q4_K_M and MLX 4-bit), user-editable list of HF repos + optional remote catalog URL in Settings, HF search (`/api/models?search=&filter=gguf|mlx`), device-fit check (RAM vs size) (#7, data layer; Settings UI is D6)
- [x] C2 Downloads: background `URLSession`, resume, progress, disk usage, delete; store under Application Support, excluded from iCloud backup (#7)
- [x] C3 `Engines/Local/GGUF`: llama.cpp via official `llama.xcframework` (pinned release, SPM binaryTarget with checksum), chat template from GGUF metadata, Metal offload, streaming tokens, cancel (#10)
- [x] C4 `Engines/Local/MLX`: `mlx-swift-lm` (MLXLLM/MLXLMCommon), load from downloaded snapshot, streaming, cancel; disabled on Simulator (no Metal GPU family) with a clear message (#11)
- [x] C5 Tests: catalog decode/merge, HF search URL building, fit check, download state machine (#7, GGUF and MLX engine tests land with C3/C4)

### Lane D — UI clone of the reference mobile design (model: sonnet-medium; starts after A merges)
- [x] D1 (#8) `Design/`: color tokens (light/dark → `Color`), radius 10pt, fonts, spacing; AnyRouter brand accent
- [x] D2 (#8) Threads sidebar: new chat, search, pinned, rename, delete; compact on iPhone, split on iPad
- [x] D3 (#9) Chat screen (message list, markdown with code blocks, copy, regenerate, stop)
- [x] D4 (#12) Model picker: grouped by source, install state, sign-in prompt for AnyRouter
- [x] D5 (#12) Hub: catalog list, search, download/delete with progress, fit badge
- [x] D6 (#13) Settings: account (sign in/out), model providers, catalog sources editor, generation defaults, appearance, about + licenses
- [x] D7 (#13) Onboarding: first launch → pick Apple / download small local / sign in

### Lane E — TestFlight (model: sonnet-low; blocked on operator secrets)
- [x] E1 (upload path untested until secrets exist) `testflight.yml`: automatic signing with the ASC API key, `xcodebuild archive` + `-exportArchive` (method `app-store-connect`, destination `upload`), unique build number, dSYMs artifact
- [x] E2 `docs/testflight.md`: app record, API key, secrets, run, internal testers, TestFlight install

## Backlog (after milestone 1; pick one, tick it, add a PR number)

- [ ] F1 Device smoke test on iPhone + iPad: AnyRouter sign-in, Apple FM chat, GGUF download + chat, MLX download + chat. Record results in the status log.
- [ ] F2 Reasoning stream: add `ChatDelta.reasoning(String)` to Core, emit it from GGUF/MLX (Qwen3 `<think>`) and AnyRouter (`reasoning` deltas), show a collapsible thinking block.
- [ ] F3 GGUF KV-cache reuse between turns (only feed the new suffix).
- [ ] F4 Newer llama.cpp: build our own xcframework (device + simulator slices) in CI from a pinned tag, replacing the b10456 pin (D12).
- [ ] F5 Bundle Inter (OFL) for closer UI parity; syntax highlighting in code blocks.
- [ ] F6 Vision: image attachments for AnyRouter vision models and Gemma 3 4B (VLM) via MLXVLM.
- [ ] F7 Mac: "Designed for iPad" on Apple silicon, then a native macOS destination.
- [ ] F8 Screenshot tests (simulator) of each main screen, compared against reference screenshots.
- [x] F15 Prompt presets: starter questions on the empty chat (tap fills the composer, long-press sends), composer presets sheet, custom presets in Settings (#28)
- [x] F9 Real-model smoke in CI: `model-smoke.yml` runs the smallest catalog GGUF through `GGUFEngine` on the Simulator, plus installer, download manager and Apple Foundation Models availability. MLX is device only. (#18)

## Local inference roadmap

Plan for advanced on-device inference (research date 2026-11-26). Docs only: no feature code lands with this section.
Engines today: GGUF through the official `llama.xcframework` (pinned b10456, D12) and MLX through `mlx-swift-lm` 3.33.0.

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

Per-model support is a set of strings in the existing `ModelDescriptor.capabilities`: `reasoning`, `spec-mtp`, `kv-turboquant`. The catalog gains an optional `drafters` list per entry (`kind`, `repo`, `file`, `sizeBytes`, `sha256`); the downloader fetches a drafter next to its target and the hub lists it as part of the same model. `validated(for:)` is the one place that enforces the rules: V-cache quantization requires flash attention, `.mtp` needs a drafter on disk and a memory fit, Qwen drafters need temperature 0, TurboQuant excludes a rotating cache.

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
- [ ] S8 **L2 and L8 on MLX** Register the Gemma 4 and Qwen MTP drafters at launch, add the catalog `drafters` field, download a drafter with its target, honour `SpeculativeDecodingConfig`/fallback reasons (greedy only for Qwen, memory policy), show "Speculative: on/off (reason)". Acceptance: Gemma 4 E2B and Qwen3.5 4B with drafter produce the same greedy text as without (token parity), device benchmark recorded here. Default stays off until the gate above passes.
- [ ] S9 **L10** TurboQuant KV on MLX behind an "Experimental" row, no rotating cache (needs S7). Acceptance: memory saving and first-256-token divergence versus f16 recorded on device; off by default.

Later (each needs its blocker first): **F4** own xcframework (device and Simulator, `common/` built, C shim) → L3 DFlash, GGUF MTP, GGUF EAGLE-3 (L7), and a decision on L9 forks (D14).

## Open questions (operator)

- Q1 Add GitHub secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (API key role App Manager).
- Q2 Create the app record in App Store Connect (bundle id `dev.anyrouter.app`, name AnyRouter).
- Q4 Resolved: icon from the public AnyRouter logo, anyrouter.dev orange accent (#8).

## Status log

- 2026-11-26 lane-ui: launch screen shows the logo on a themed background, AppIcon dark and tinted variants, asset test; local checks skipped
- 2026-11-26 lane-docs: local inference roadmap (L1-L10 verdicts, shared Core shapes, PR sequence S1-S9), decision D14; docs only, local checks skipped
- 2026-11-26 lane-ci: unsigned debug IPA workflow `device-ipa.yml` and `docs/sideload.md`; local checks skipped
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
