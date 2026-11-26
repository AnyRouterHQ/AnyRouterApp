# PLAN.md — AnyRouter for iPhone and iPad

Owner: operator. Manager: main Claude session. Workers: lane agents (see AGENTS.md).
Last updated: 2026-11-26.

## Goal

A native SwiftUI app **AnyRouter** for iPhone and iPad that copies the Atomic Chat mobile UI and UX
(rebranded to AnyRouter) and chats with:

1. **Apple Foundation Models**, on device
2. **Local Hugging Face models**, GGUF (llama.cpp) and MLX, from a configurable catalog
3. **AnyRouter models**, after **Sign in with AnyRouter** (OAuth + PKCE)

**Milestone 1:** an ad-hoc signed build installed on the operator's own iPhone and iPad.

## Decisions (from the operator interview, 2026-11-26)

| # | Decision | Why |
|---|---|---|
| D1 | Native SwiftUI clone, not the Tauri fork | Operator choice. Native FoundationModels/MLX, small app. The look is copied from Atomic's React source. |
| D2 | Public open-source repo `github.com/AnyRouterHQ/AnyRouterApp`, Apache-2.0 | Operator choice. Public also gives free macOS CI minutes. |
| D3 | Both GGUF (llama.cpp) and MLX engines behind one `ChatEngine` protocol | Operator choice |
| D4 | Milestone 1 = ad-hoc device build | Operator choice. Needs Team ID + ad-hoc profile (see Open questions). |
| D5 | iOS/iPadOS 26.0 minimum, universal app (iPhone + iPad) | FoundationModels needs 26. One target. |
| D6 | Bundle id `dev.anyrouter.app`, display name `AnyRouter` | Matches the `dev.anyrouter.*` family. |
| D7 | XcodeGen `project.yml`, no committed `.xcodeproj` | Parallel lanes add files without pbxproj conflicts. |
| D8 | CI on GitHub Actions macOS runners is the only build | Operator Mac has no Xcode and a no-local-build rule. |
| D9 | OAuth: dynamic client registration (`/api/v1/mcp/oauth/register`) + PKCE + loopback `127.0.0.1` callback via `ASWebAuthenticationSession` | Pattern proven on device in an earlier AnyRouter iOS prototype; the server rejects custom URL schemes. |
| D11 | Config: `Config/Base.xcconfig` (committed) + `Config/Local.xcconfig` (gitignored) for Team ID; CI secrets for signing | Open source: no personal values in git. |
| D12 | UI-facing service protocols live in `Features/Services/`: `AccountService` (sign-in state; lane B conforms, `@MainActor @Observable` class) and `ModelHubService` (catalog, download state, search, custom repos; lane C conforms). Lane D ships inert defaults in `AppState` (`account`, `hub`); B/C assign their real service there. | UI never imports engine types. |
| D13 | Markdown rendering uses `gonzalezreal/swift-markdown-ui` (MarkdownUI 2.4.x) | Maintained, SwiftUI-native, themeable to Atomic's markdown.css. |
| D10 | Persistence: SwiftData for threads/messages; Keychain for the AnyRouter key; `UserDefaults` for settings | Simplest native stack. |
| D12 | llama.cpp is pinned to release b10456 through a local package `Packages/LlamaBinary` (binaryTarget + checksum) | b10456 is the newest official xcframework with iOS Simulator and device slices. From b10488 on, releases ship device slices only, and CI builds for Simulator. Revisit when upstream restores the simulator slice. |

## Out of scope for v1

Atomic features not ported in v1: agents/skills, MCP connectors, projects, RAG/vector DB, audio, images, videos,
local API server, system monitor, remote LAN, cloud sync, macOS target. Keep the UI slots only where Atomic's
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
Design/                          lane D   tokens ported from Atomic index.css, typography, components
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
- [x] A5 `THIRD_PARTY_NOTICES.md` (Atomic Chat Apache-2.0 notice), `README.md` (build steps, screenshots later) (#3)
- [x] A6 Open-source CI/CD hygiene: `gitleaks.yml` on PR + push, `dependabot.yml` (github-actions, swift), `.github/pull_request_template.md`, issue templates (bug, feature), `CONTRIBUTING.md` pointing at AGENTS.md, `SECURITY.md`; wire `Config/*.xcconfig` into `project.yml` (#3)

### Lane B — Apple + AnyRouter engines, auth (model: sonnet-medium; auth is a security path)
- [x] B1 `Engines/Apple`: `AppleFoundationEngine` (availability states, streaming snapshots → append-only deltas, instructions from system prompt) (#2)
- [x] B2 `Engines/AnyRouter/Auth`: `OAuthClient` + `KeychainStore` (lane brief gives the prototype to port); sign in, sign out, key status; client name "AnyRouter for iOS" (#2)
- [x] B3 `Engines/AnyRouter`: `GET /api/v1/models` → `ModelDescriptor`s; `POST /api/v1/chat/completions` with `stream: true` SSE parser; app attribution headers per AnyRouter docs; 401 → signed-out state (#2)
- [x] B4 Tests: PKCE challenge, SSE parsing (fixtures incl. `[DONE]`, usage chunk, error chunk), models decoding (#2)

### Lane C — local Hugging Face models (model: sonnet-high)
- [x] C1 `Engines/Local/Catalog`: bundled `catalog.json` (curated small models that fit phones: e.g. Qwen3 0.6B/1.7B/4B, Gemma 3 1B/4B, Llama 3.2 1B/3B, in GGUF Q4_K_M and MLX 4-bit), user-editable list of HF repos + optional remote catalog URL in Settings, HF search (`/api/models?search=&filter=gguf|mlx`), device-fit check (RAM vs size) (#7, data layer; Settings UI is D6)
- [x] C2 Downloads: background `URLSession`, resume, progress, disk usage, delete; store under Application Support, excluded from iCloud backup (#7)
- [ ] C3 `Engines/Local/GGUF`: llama.cpp via official `llama.xcframework` (pinned release, SPM binaryTarget with checksum), chat template from GGUF metadata, Metal offload, streaming tokens, cancel
- [ ] C4 `Engines/Local/MLX`: `mlx-swift-lm` (MLXLLM/MLXLMCommon), load from downloaded snapshot, streaming, cancel; disabled on Simulator (no Metal GPU family) with a clear message
- [x] C5 Tests: catalog decode/merge, HF search URL building, fit check, download state machine (#7, GGUF and MLX engine tests land with C3/C4)

### Lane D — UI clone of Atomic Chat mobile (model: sonnet-medium; starts after A merges)
- [x] D1 (#8) `Design/`: port tokens from `Atomic-Chat/web-app/src/index.css` (oklch light/dark → `Color`), radius 10pt, fonts from `styles/font.css`, spacing; AnyRouter brand accent
- [x] D2 (#8) Threads sidebar (Atomic `left-sidebar/`, `ThreadList.tsx`): new chat, search, pinned, rename, delete; compact on iPhone, split on iPad
- [x] D3 (#9) Chat screen (Atomic `ChatInput.tsx`, message list, markdown with code blocks, copy, regenerate, stop)
- [ ] D4 Model picker (Atomic `DropdownModelProvider.tsx`): grouped by source, install state, sign-in prompt for AnyRouter
- [ ] D5 Hub (Atomic `routes/hub`): catalog list, search, download/delete with progress, fit badge
- [ ] D6 Settings (Atomic `routes/settings`): account (sign in/out), model providers, catalog sources editor, generation defaults, appearance, about + licenses
- [ ] D7 Onboarding (Atomic `onboarding/`): first launch → pick Apple / download small local / sign in

### Lane E — ad-hoc signing and install (model: sonnet-low; blocked on operator secrets)
- [ ] E1 `release-adhoc.yml`: import cert + profile from secrets, `xcodebuild archive` + `-exportArchive` (method `release-testing`/ad-hoc), upload IPA artifact
- [ ] E2 Install doc: Apple Configurator 2 or OTA manifest page; size report of the IPA

## Open questions (operator)

- Q1 Apple Developer **Team ID**, and is the account paid (ad-hoc needs a paid team)?
- Q2 Device **UDIDs** of the iPhone and iPad (for the ad-hoc profile), or permission to register them in the Apple Developer portal.
- Q3 GitHub secrets for signing: `IOS_CERT_P12_BASE64`, `IOS_CERT_PASSWORD`, `IOS_ADHOC_PROFILE_BASE64`, `APPLE_TEAM_ID`.
- Q4 AnyRouter brand assets (app icon, accent color) — default: anyrouter.dev favicon/logo and accent.

## Status log

- 2026-11-26 manager: interviewed operator, wrote AGENTS.md + PLAN.md + base config, created public repo AnyRouterHQ/AnyRouterApp, started lanes A, B, C.
- 2026-11-26 lane-A: scaffold, Core contract, app shell, CI workflow (#1); local checks skipped
- 2026-11-26 lane-D: design tokens, adaptive shell, threads sidebar, AnyRouter icon (#8); local checks skipped
- 2026-11-26 lane-D: chat screen, composer, markdown (MarkdownUI), view model tests (#9); AppState now registers the Apple and AnyRouter engines; local checks skipped
- 2026-11-26 lane-A: hygiene (gitleaks, dependabot, templates, README, notices) (#3); PR #1 merged, CI green
- 2026-11-26 lane-B: Apple + AnyRouter engines, OAuth sign-in, SSE/PKCE tests (#2); local checks skipped, CI is the gate
- 2026-11-26 lane-C: catalog, HF client, device fit, background downloads and installer with tests (#7); local checks skipped
