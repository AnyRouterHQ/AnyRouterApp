# Local agent: device tools, Siri and Shortcuts, on-device models

Research date: 2026-11-26. Research only, no app code. Scope: what AnyRouter can call on the device as agent tools, how Siri and Shortcuts can call AnyRouter, how Foundation Models and local engines handle tools, and a first design.

How to read the labels. **Verified** means read in Apple's developer documentation or a WWDC26 session transcript on this date. **Known** means stable platform behavior that was not re-read today, so confirm it when the task is built. **Inferred** means my reading of the evidence. Secondary blog posts were not used as evidence.

Version note. The Apple docs fetched today already cover iOS 27 (for example `ToolIntent` is marked iOS 27.3). The app still targets iOS and iPadOS 26.0 (decision D5), so anything marked 27 below must sit behind `#available(iOS 27, *)` and may only be an extra.

## Summary

- Keep the agent loop we have (engine runs the loop, `ToolHost` owns approval and execution). It works for Apple, MLX, GGUF and cloud on iOS 26, and it is the single place to enforce confirmations. Apple's own security guidance says to put confirmation in one deterministic hook that runs before every tool (WWDC26 347).
- Add device tools as `BuiltInTool` conformances, in this order: `ocr_image`, `calendar_search`, `reminders` (search, create with confirmation), `contacts_lookup`, `place_search`, `weather`, `translate_text`, `run_shortcut`. All but the last use public frameworks with one system prompt or none.
- The Apple model fits at most 3 to 5 tools per request and has a small context (4096 tokens documented for 26.x, larger on newer models). Our `AppleDynamicTool.maxTools = 8` is too high. Select 4 tools per request for Apple and local engines.
- A user's own shortcut can be a tool through the `shortcuts://run-shortcut` URL scheme, but only for names the user registers (no public API lists shortcuts), it leaves the app, and it can only return text through x-callback. Ship it after the read-only tools, always ask first.
- "Ask AnyRouter" from Siri and Shortcuts works on iOS 26 with an App Intent plus an App Shortcut. No entitlement is needed. There is no assistant schema for chat apps (the `.assistant.activate` schema is Japan only, side button).
- The new Siri AI route on iOS 27.3 (`@AppIntent(.tool)`, app skills) is a Developer Preview. It does not work for App Store or external TestFlight builds. Adding any tool intent also removes your App Shortcuts from Siri. Do not depend on it. Build the iOS 26 intent first.
- Foundation Models on iOS 27 adds `LanguageModel`, `DynamicProfile`, `.onToolCall`, `ToolCallingMode`. Apple's open source `ChatCompletionsLanguageModel` can back a session with any OpenAI-compatible server, which includes AnyRouter. Interesting, but it needs the 27 SDK and we do not need it for our own loop.
- Local tool calling: MLX has parsers for many model families in mlx-swift-lm (we are on 3.33.0, the latest). GGUF tool calling lives in llama.cpp's `common/` library, which our xcframework does not build yet. Plan T7 MLX first.
- Permission UX: ask in context, at the first tool call, with our own sheet before the system prompt. Sensitive reads (calendar, contacts, location) are off by default and add a "taint" rule: after a sensitive read, outbound tools need approval for the rest of the turn.
- Loop limits: 4 rounds on Apple and local engines, 8 on cloud; reads can run in parallel; every write or external action asks each time and shows the exact payload; no "always allow" for writes.

## 1. On-device capabilities as agent tools

Columns: what the tool can do, the access it needs, limits that shape the tool, and the verdict. "Plist" means an Info.plist usage string. "Capability" means an App ID capability in the developer account.

| Capability | API | Access | Limits that matter | Verdict |
|---|---|---|---|---|
| App Intents (our own actions) | AppIntents | None | Intents we define run in our process. They are not a way to call other apps. WWDC26 lab quote in secondary sources says no API calls another app's intents (not verified). | Expose, not consume (section 2) |
| Run a user shortcut | URL scheme `shortcuts://run-shortcut?name=&input=text&text=` (verified, Apple Shortcuts guide) | None | Opens the Shortcuts app and switches away from our app. Input is text or clipboard. The page does not describe a result. x-callback-url (`x-success`) is Known, confirm. No API lists the user's shortcuts. `RunSystemShortcutIntent` (iOS 27) works only from a widget button and exposes no shortcut internals (verified). | Wave 2, user-registered names, ask every time |
| Calendar and Reminders | EventKit | Plist `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, `NSRemindersFullAccessUsageDescription` (Known). Runtime: `requestFullAccessToEvents`, `requestWriteOnlyAccessToEvents`, `requestFullAccessToReminders` | Verified: there is no read-only level. Reading needs full access. Write-only access can create events but cannot read any event, even ones we created. `EKEventEditViewController` lets the user review and save an event without calendar permission (Known since iOS 17, confirm). | Read: full access, capped. Create: write-only or the edit sheet |
| Contacts | Contacts, ContactsUI | Plist `NSContactsUsageDescription` (Known) | Verified: since iOS 18 the user may grant a subset (limited status). `ContactAccessButton` lets the user add more contacts while searching. `CNContactPickerViewController` needs no permission (Known). The Notes field needs a separate entitlement; we do not need it. | Lookup with limited access in mind |
| Photos | PhotosUI, PhotoKit | `PhotosPicker` needs no permission. Library access needs `NSPhotoLibraryUsageDescription` (Known) | Verified: limited library mode since iOS 14, Apple recommends the picker when read-only access is enough. | Use the picker (already an attachment flow). Not an autonomous tool |
| Health | HealthKit | Capability, plist read and update strings (Known) | Verified: the app cannot tell if read access was denied (you just get no samples), and the user can grant only a recent window. App Review limits on health data use are Known, confirm guideline 5.1.3 before any cloud use. | Defer. Local-only models at most |
| Maps and places | MapKit (`MKLocalSearch`, `MKGeocodingRequest`, `MKReverseGeocodingRequest`, cycling directions) | None for search | Verified: geocoding requests and `MKAddress` arrived in 2025. Search is region based. | Ship: `place_search` |
| Location | CoreLocation | Plist `NSLocationWhenInUseUsageDescription` (Known). Verified: ask only when the user reaches a feature that needs it, prefer When in Use | One-shot fix is enough for weather and places. A user may grant approximate location only (Known). | Ship, approximate is fine |
| Weather | WeatherKit | Capability on the App ID | Verified: 500,000 API calls per month per Apple Developer Program membership, paid tiers above. Attribution of Apple Weather is required (Known). Needs network. | Ship: `weather` (operator must enable the capability) |
| Music | MusicKit | Capability, `MusicAuthorization.request()` (verified API), plist `NSAppleMusicUsageDescription` (Known) | Catalog search and library need authorization. Playback needs a subscription (Known). | Defer. Low value for a chat agent |
| Files | `fileImporter`, `UIDocumentPickerViewController` | None | The user picks files; we get security-scoped URLs. No blanket access to Files (Known). | Use the picker. Our attachments flow already covers it |
| Notes | None | n/a | No public API reads Apple Notes (inferred: the docs list a notes schema domain, but it is for apps that implement notes). Share sheet or `ShareLink` can hand text to Notes. | No tool. Offer "Share" on replies |
| Messages and Mail | MessageUI compose sheets | None | We present a sheet, the user taps Send. We cannot read messages or send silently (Known). | Wave 2: `compose_message` and `compose_mail` as write tools |
| Clipboard | `UIPasteboard`, `PasteButton` | None, but verified: since iOS 14 the system shows a notice when an app reads content that came from another app without user intent | A tool that reads the clipboard would trigger that notice at a time the user did not choose. | No tool. Keep the composer paste |
| Spotlight | CoreSpotlight (`CSSearchableIndex`, `CSUserQuery`), `IndexedEntity` | None | Only our own app's index (Known). Verified: iOS 27 adds `SpotlightSearchTool`, a ready-made Foundation Models tool over our index, and a July 2026 sample app for natural-language search. | Wave 2: index chat threads, tool for recall |
| Vision OCR | Vision (`RecognizeTextRequest`, `RecognizeDocumentsRequest` iOS 26 verified) | None | On device, no network. iOS 27 adds `OCRTool` and `BarcodeReaderTool` for Foundation Models sessions. Verified: they are not available in Simulator. | Ship: `ocr_image` on the chat's image attachments |
| Speech to text | Speech (`SpeechAnalyzer`, `SpeechTranscriber`, iOS 26 verified) | Microphone for live audio. Whether speech-recognition authorization is also needed for `SpeechAnalyzer` is not verified | Models install through `AssetInventory` per locale (verified). D17 already picks this for dictation. | Dictation feature, not an agent tool |
| Translation | Translation (`TranslationSession`) | None | Verified: without UI you create a session with `init(installedSource:target:)`, which throws if the languages are not installed. The SwiftUI `translationTask` path can offer a download. | Ship: `translate_text` (report "language not installed" as a tool error) |

Permissions that need Info.plist strings or capabilities are the operator's setup, not secrets. None of them needs a special Apple approval, except Health clinical records and the Private Cloud Compute model (section 3).

### What a tool must not do

- Read the clipboard, the photo library or Files on its own. Use pickers and the attachment flow.
- Ask a system permission at launch or in onboarding. Apple's Core Location guidance (verified) is to ask only when the person reaches the feature.
- Return whole records. Calendar events return title, start, end, place. Contacts return the name and the one field asked for. This keeps the 4k window usable and limits what leaves the device on a cloud turn.

## 2. Exposing AnyRouter to Siri, Apple Intelligence and Shortcuts

### Works today on iOS 26 (no entitlement)

- An `AppIntent` with a text parameter, for example `AskAnyRouterIntent(prompt: String)`, returning the answer as a value and a dialog. It shows in the Shortcuts app, Spotlight, the Action button and Siri.
- An `AppShortcutsProvider` with phrases that contain the app name, so "Ask AnyRouter" works from first install. Known constraint to confirm: App Shortcut phrases can only embed entity and enum parameters, not free text, so Siri asks "What do you want to ask?" for the `prompt` parameter.
- Shortcuts can also pass our result into other actions, including the new "Use Model" action (verified, WWDC26 310).
- iOS 26 runtime knobs: `supportedModes` (foreground or background, verified). iOS 27 adds `LongRunningIntent` for extra background time (verified).
- Confirmation inside an intent: `requestConfirmation(conditions:actionName:dialog:)` (verified in the App Intents updates).
- Intent context has no chat UI. From an intent, only read tools should be allowed. A write tool needs `requestConfirmation` or must be refused.

### Not available

- There is no assistant schema that makes Siri hand a free-form chat to a third-party app. The primary schema domains are audio, calendar, camera, clock, mail, maps, messages, notes, phone, photos, reminders, system and in-app search, video. The only `assistant` domain has one schema, `activate`, "available only in Japan" and for the iPhone side button (verified, iOS 26.2).
- I found no Apple documentation of a chatbot extension point ("ask <app>" as a model provider). Secondary blog posts mention one; treat that as unverified.

### Siri AI Developer Preview (iOS 27.3 docs)

Verified in Apple's docs and WWDC26 sessions 240, 343, 344, 347:

- A custom intent becomes a tool Siri can call with `@AppIntent(.tool)` (protocol `ToolIntent`, iOS 27.3). Apps can add titles and descriptions for the model, `GenerableEntity` so the model builds parameters directly, `CardSnippet` for answers, and "app skills": Markdown `SKILL.md` files in a `Skills.skillsbundle` that guide multi-step flows (guidance only, not deterministic).
- Without naming the app, a request reaches us only when our app is in the foreground, a Live Activity is active, or the user continues a Siri conversation that already mentioned us. In the background the user must say our name.
- Not for release: the preview "isn't available to external testers in TestFlight or to versions of your app that you publish on the App Store". It works for development-signed builds and internal TestFlight. Re-check when it leaves preview.
- Adding any tool intent makes our App Shortcuts unavailable to Siri (they stay in Spotlight and the Action button). So the iOS 26 shortcut and the tool intent cannot both serve Siri.
- Security features we would adopt: risk-based confirmations the system adds by schema side effects, `authenticationPolicy` (for schema intents it can be raised, not lowered) so risky intents need an unlocked phone, `IntentVisibility.internal` to hide sensitive properties.
- Other new App Intents pieces (iOS 27): `RunSystemShortcutIntent` (widgets only), `UndoableIntent`, `CancellableIntent`, `OwnershipProvidingEntity`.

Recommendation: ship the iOS 26 intent and shortcut. Prototype the tool-intent variant on an internal TestFlight build only, behind `#available(iOS 27.3, *)`, and keep the App Shortcut for everyone else.

## 3. Apple Foundation Models and local engines

### Tool protocol and guided generation (verified)

- `Tool` (iOS 26.0): `name`, `description`, `Arguments: ConvertibleFromGeneratedContent`, `call(arguments:)` returning a `PromptRepresentable` (a `String` or a `@Generable` type). Tools are `Sendable` and may run concurrently. A tool can feed another (back-to-back calls).
- `@Generable` and `@Guide` give constrained sampling: the output always matches the schema. `Arguments = GeneratedContent` with a dynamic `GenerationSchema` works, which is what `AppleDynamicTool` does for MCP tools.
- `includesSchemaInInstructions` defaults to true. Only turn it off for a tool the model was trained on.
- Everything counts toward the window: instructions, tool definitions, tool arguments and outputs, `@Generable` schemas, replies.

### Limits and quality (verified unless marked)

- Context: the guide says 4096 tokens per session. `SystemLanguageModel.contextSize` and `tokenCount(for:)` exist since 26.4 (back-deployed). A WWDC26 sample prints 8192 on the new model, so read the value, never hard-code it. The Private Cloud Compute model has 32,000 tokens, reasoning, a daily per-user limit, and needs a managed entitlement request (iOS 27).
- Apple's advice: "no more than three to five tools per request", short descriptions and short `@Guide` text, skip tools when you can fetch the data yourself and put it in the prompt.
- Model versions: 26.0 to 26.3, 26.4, and 27.0 differ. Apple says 26.4 improved tool calling and instruction following, and 27 improved again. No published tool-calling accuracy numbers exist. We must measure on our own prompts (task LA11), and version prompts with `#available` checks as Apple suggests.
- Errors: exceeding the window throws `LanguageModelError.contextSizeExceeded`. The documented recovery is a new session built from a trimmed transcript.
- Availability depends on device, region and Apple Intelligence being on (`SystemLanguageModel.availability`).

### iOS 27 agent APIs (verified, WWDC26 241, 242, 347)

- `LanguageModelSession.DynamicProfile` with per-phase model, instructions and tools.
- Lifecycle modifiers: `.onToolCall { call in ... }` runs before every tool call and a thrown error stops the call. `.historyTransform` runs before each model step and is meant for spotlighting (delimiting untrusted tool output) and redaction. Apple's own agent example uses exactly these two for confirmation and prompt-injection defence.
- `GenerationOptions.ToolCallingMode` with `allowed`, `disallowed`, `required`. With `required` the model loops until you provide an exit (a throwing tool or a changed mode).
- `transcriptErrorHandlingPolicy` (`revertTranscript` or `preserveTranscript`), settable `transcript`. Rewriting history invalidates the KV cache and can confuse the model. Append when you can.
- `LanguageModel` protocol: any local or server model can back a `LanguageModelSession`. Apple ships `SystemLanguageModel` and `PrivateCloudComputeLanguageModel` and open-sources `CoreAILanguageModel` and `MLXLanguageModel`. Anthropic and Google publish Swift packages for their models (per session 241; not inspected).
- Patterns Apple names: baton-pass (switch profile through a tool) and phone-a-friend (tool spawns a short child session). The utilities package adds rolling windows, dropping completed tool calls, summarizing history, and `Skills`.

### How others structure the agent loop on it

- Apple's pattern is a session that owns the loop. The model emits a tool call, the framework runs the tool, feeds the output back, repeats until a plain reply. Apple says to treat the transcript as the state.
- SwiftAgent (below) keeps the same shape and adds one idea worth copying: a tool can throw a typed `ToolRunRejection` that goes back to the model as a structured error without ending the loop, so the model can fix its arguments.
- Our design already puts execution and approval in `ToolHost`, outside any one model API. That is the right boundary for four engines.

### MLX Swift on device

- mlx-swift-lm (MIT, pushed 2026-11-26, we use 3.33.0 from 2026-11-17) has a `Tool/` module: `ToolCallProcessor`, `ToolCallFormat` with parsers for Qwen 3.5 XML, Gemma functions, Llama 3, Mistral, GLM 4, Kimi K2, MiniMax M2, Pythonic, Harmony and generic JSON, plus `ToolCallPolicy` (recovery of calls in another dialect, and a `strict` validation mode "to check arguments before automatic tool dispatch"). This is what T7 needs for MLX.
- `MLXGuidedGeneration` gives grammar-constrained output (JSON Schema or EBNF) for any MLX model. `MLXFoundationModels` bridges to `LanguageModelSession` and needs the iOS 27 SDK.
- Small models call tools unreliably. Use strict validation, at most 3 tools, short descriptions, and an eval set before enabling the switch.

### llama.cpp (GGUF)

- Tool calling lives in `common/chat`, used by `llama-server --jinja`. Native formats include Llama 3.x, Hermes and Qwen 2.5, Mistral Nemo, Functionary, DeepSeek R1 and GPT-OSS Harmony. Other templates use a "generic" handler that costs more tokens (llama.cpp docs/function-calling.md, verified).
- Our xcframework builds `libllama` and `libmtmd` only. PLAN F4 notes `common/` is not built yet. So GGUF tool calling needs either that build, or a Swift prompt renderer and parser per model family (the work T7 describes). Inferred: do GGUF after MLX.

### Core AI (iOS 27)

- Core AI is Apple's new on-device model framework (sessions 324 and 326). `apple/coreai-models` (BSD-3-Clause) has export recipes and Swift runtime utilities, including a `CoreAILanguageModel`. Needs the iOS 27 SDK. Not part of this plan; note it for the local engines roadmap.

## 4. Open source worth learning from

Stars and push dates read from the GitHub API on 2026-11-26.

| Repo | License | Maturity | What to take |
|---|---|---|---|
| apple/foundation-models-utilities | Apache-2.0 | 581 stars, pushed 2026-11-02, version 1.0.0-beta6 | `ChatCompletionsLanguageModel` (any OpenAI-compatible server, so AnyRouter), history modifiers (rolling window, drop completed tool calls, summarize), `Skills`. Beta. Needs iOS 27 types. |
| ml-explore/mlx-swift-lm | MIT | 881 stars, pushed today, already a dependency | Tool call parsers and policy (above) |
| ml-explore/mlx-swift-examples | MIT | 2705 stars, pushed 2026-11-09 | Reference apps for local chat with tools |
| huggingface/AnyLanguageModel | Apache-2.0 | 992 stars, pushed 2026-11-25 | A drop-in copy of the Foundation Models API for MLX, llama.cpp, Core ML, Ollama, OpenAI, Anthropic, Gemini. Good reference for one tool interface across backends. Too many optional dependencies to adopt for our own loop. |
| mattt/iMCP | MIT | 2007 stars, pushed 2026-11-25 | A macOS app that serves Calendar, Contacts, Messages, Reminders, Maps, Location, Weather through MCP. Best map of which tools people want and how to word their descriptions. macOS only, so a reference not a dependency. |
| SwiftedMind/SwiftAgent | MIT | 233 stars, last push 2026-01-23 | Agent loop with FoundationModels-style tools, structured tool rejection, transcript and token usage. Smaller and older, read it for the loop and rejection design. |
| modelcontextprotocol/swift-sdk | MIT moving to Apache-2.0 (the repo says the project is in transition) | 1585 stars, pushed today | We chose our own small MCP client (T1). Keep that decision. |
| huggingface/swift-transformers | Apache-2.0 | 1367 stars | Tokenizers and chat templates. Not needed now. |
| apple/coreai-models | BSD-3-Clause | 2383 stars, pushed 2026-11-22 | Core AI export and runtime, iOS 27 |

Apple sources worth reading in full: WWDC26 347 (agentic security), 242 (agentic apps with Foundation Models), 241 (what's new), 339 (bring an LLM provider), 343 and 344 (Siri, App Intents), 345 (App Intents capabilities), 310 (Shortcuts, Use Model), 246 (Spotlight search tool), 232 (local agentic AI with MLX on the Mac).

## 5. Recommended design

Goal: an on-device agent that uses the phone's own data safely, on any engine, without a second loop.

### Data shape first

Today `BuiltInTool` says "built-in tools only read". Device tools need a class. Add it to the protocol instead of a parallel type:

```swift
enum SideEffect { case read, sensitiveRead, write, external }   // external: leaves the app or cannot be undone
protocol BuiltInTool { /* existing */ var sideEffect: SideEffect { get }; var permission: DevicePermission? { get } }
```

- `read`: runs without asking (as today).
- `sensitiveRead`: calendar, reminders, contacts, location. Needs the permission, then runs. Marks the turn as tainted.
- `write`: creates something the user can undo (a reminder, an event). Always shows a confirmation card with the exact payload.
- `external`: send a message, run a shortcut, anything outside the app. Confirmation every time, never "always allow".

### First tools (8)

1. `ocr_image`: Vision text and document recognition on the chat's image attachments. No permission. Read.
2. `calendar_search`: events in a date range, 20 at most, title, time, place. Full access. Sensitive read.
3. `reminders`: search, and `reminder_create` behind a confirmation card. Full access. Sensitive read and write.
4. `contacts_lookup`: name to phone or email, only the field asked for, aware of limited access. Sensitive read.
5. `place_search`: MapKit local search and geocoding near a region or the approximate location. Read.
6. `weather`: WeatherKit for a place or the approximate location. Read. Needs the capability and the attribution line.
7. `translate_text`: Translation, installed languages only. Read.
8. `run_shortcut`: runs a shortcut the user registered in Settings (name, description, optional text input). External. Wave 2 because the app leaves the foreground and the loop must suspend and resume on the x-callback.

Existing tools stay: `fetch_url`, `web_search`, `current_datetime`, `calculator`, `read_attachment`. Event creation uses `EKEventEditViewController` (the user's own save is the confirmation).

Not in the first set: Health, Music, Notes, clipboard, Files, Messages and Mail. Reasons are in section 1.

### Which tools the model sees

Apple and local models take 3 to 5 tools. Cloud models take many. Add a small selector that picks the tools per request from tool groups (Calendar and Reminders, Places and Weather, Contacts, Vision, Web). Rules: Apple and local get at most 4, chosen by group switches then by simple keyword and attachment hints. Cloud gets all enabled tools. Lower `AppleDynamicTool.maxTools` from 8 to 4. Cap a tool result at about 1500 characters for Apple (T6 caps at 6000 today, a third of a 4096-token window) and keep 6000 for cloud; on 26.4 and later budget with `tokenCount(for:)`.

### Permission UX

- Nothing is requested at launch or in onboarding.
- First call of a device tool while permission is "not determined": show our approval dialog first ("AnyRouter wants to read your calendar to answer this"), with Allow and Not now. Only Allow triggers the system prompt. Reason: a model-triggered system prompt with no context gets denied, and a denied system prompt cannot be asked again.
- Permission denied: the tool returns "Calendar access is off. Ask the user to enable it in Settings." The chat row shows an "Open Settings" button. The tool does not retry.
- Settings > Integrations gets a section "On this device". Each tool shows its switch and a status (Not asked, Allowed, Off in Settings). Sensitive tools are off by default. Tools without a prompt (OCR, translate) are on.
- Ask for the least access: write-only for event creation, limited contacts with `ContactAccessButton` when a lookup finds nothing, approximate location for weather and places.
- Cloud turns: the first time a sensitive tool result would go to a cloud model in a chat, say so ("This sends calendar entries to the model you chose"). Apple and local models never need this notice.

### Prompt injection and data leaving the device (WWDC26 347)

- Treat every tool result as untrusted. Wrap tool output in delimiters before it re-enters the prompt (spotlighting), as Apple's example does in `.historyTransform`. We can do the same in the shared host path, so all engines get it.
- Taint rule: after a `sensitiveRead` in a turn, outbound tools (`fetch_url`, `web_search`, MCP tools, `external` tools) ask for approval for the rest of that turn. This extends T11's `ExfiltrationGuard`. It cuts the case "a web page tells the model to send your calendar to a URL".
- Confirmations live in the host, not in the prompt. A system prompt that says "ask first" is not a control.
- Intent context (Siri, Shortcuts): read tools only. Writes refuse, or use `requestConfirmation`.

### Loop shape

- Engine runs the loop, host executes (as in T3 and T4).
- Max rounds: 8 on cloud (today), 4 on Apple and local. At most 2 calls per round, parallel only for reads. Writes and external calls run alone.
- Per-tool timeout 20 s (today). Whole turn 60 s on device engines.
- Stop on a repeated identical call. On the last round turn tools off (`tool_choice: none` on cloud; on Apple 27 `ToolCallingMode.disallowed`, on 26 build the final reply in a new session from the trimmed transcript).
- A rejected or invalid call returns a structured tool error to the model (keep SwiftAgent's idea) and counts as a round.
- Confirmation needs the app in the foreground. If the app is backgrounded mid-turn, the pending write waits and the turn is marked "waiting for you".
- Steps are kept for display only, not replayed (decision in T3). Keep that.

### Risks and open questions

- Tool-calling quality of the on-device model has no published numbers. We need a small eval (about 20 prompts, per engine) before turning tools on by default for Apple and local engines.
- WeatherKit needs the capability on our App ID and a Developer Program account action. Operator task.
- Health stays out until the operator decides on App Review and cloud use.
- The Siri AI preview may change before release (Apple says the API may change). Keep it isolated.
- Whether `SpeechAnalyzer` also needs speech-recognition authorization, and the exact App Shortcut phrase rule, must be confirmed when built.
- Local builds are skipped on this Mac (rule). Everything above came from docs and repo metadata, nothing was compiled.

## Sources

Apple developer documentation (fetched 2026-11-26):

- https://developer.apple.com/documentation/foundationmodels/tool
- https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
- https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
- https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- https://developer.apple.com/documentation/foundationmodels/languagemodel
- https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile
- https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct
- https://developer.apple.com/documentation/updates/foundationmodels
- https://developer.apple.com/documentation/updates/appintents
- https://developer.apple.com/documentation/appintents/app-schema-domains
- https://developer.apple.com/documentation/appintents/app-schema-domain-assistant
- https://developer.apple.com/documentation/appintents/siri-ai-developer-preview
- https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri
- https://developer.apple.com/documentation/appintents/toolintent
- https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills
- https://developer.apple.com/documentation/appintents/runsystemshortcutintent
- https://developer.apple.com/documentation/corespotlight/spotlightsearchtool
- https://developer.apple.com/documentation/vision/ocrtool
- https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- https://developer.apple.com/documentation/contactsui/contactaccessbutton
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/translation/translationsession
- https://developer.apple.com/documentation/speech/speechanalyzer
- https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
- https://developer.apple.com/weatherkit/
- https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios

WWDC26 sessions (transcripts read): 241 What's new in the Foundation Models framework, 242 Build agentic app experiences with the Foundation Models framework, 319 Build with the new Apple Foundation Model on Private Cloud Compute, 339 Bring an LLM provider to the Foundation Models framework, 347 Secure your app: mitigate risks to agentic features, 310 What's new in Shortcuts, 343 and 344 and 240 (Siri with App Intents and App Schemas), 345 What's new in App Intents, 246 LLM search using Core Spotlight. Listed from the session index but only skimmed: 232, 324, 326.

Open source: github.com/apple/foundation-models-utilities, github.com/ml-explore/mlx-swift-lm, github.com/apple/coreai-models, github.com/huggingface/AnyLanguageModel, github.com/mattt/iMCP, github.com/SwiftedMind/SwiftAgent, github.com/modelcontextprotocol/swift-sdk, github.com/ggml-org/llama.cpp (docs/function-calling.md).
