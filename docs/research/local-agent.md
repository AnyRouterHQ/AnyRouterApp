# Local agent: device tools, Siri and Shortcuts, on-device models

What AnyRouter can call on the device, how Siri and Shortcuts can call AnyRouter, and how Foundation Models, MLX and llama.cpp handle tools. The loop, memory and budgets are in `agent-design.md`. PLAN.md lists the open work (LA2 to LA16, T7).

**Verified** means read in Apple's documentation or a WWDC26 transcript (see Sources). **Known** means stable platform behavior to confirm when built. **Inferred** means a reading of the evidence. The app targets iOS and iPadOS 26.0 (D5), so anything marked 27 sits behind `#available(iOS 27, *)` and is an extra.

## Rules that hold

- The engine runs the loop and `ToolHost` owns approval and execution. Apple's guidance is one deterministic confirmation hook before every tool (WWDC26 347). A system prompt that says "ask first" is not a control.
- Device engines see at most 4 tools (Apple advises 3 to 5, Verified). Cloud sees all enabled tools. Groups (Calendar and Reminders, Places and Weather, Contacts, Vision, Web) choose by switch, then by keyword and attachment hints.
- Tool results are small. Return title, start, end and place for an event, and the name plus the one field asked for for a contact. This keeps the 4k window usable and limits what leaves the device on a cloud turn.
- Side effects are classes on `BuiltInTool` (`SideEffect`): `read` runs without asking. `sensitiveRead` (calendar, reminders, contacts, location) needs the permission and taints the turn. `write` creates something undoable and always shows a card with the exact payload. `external` (send a message, run a shortcut) asks every time and never offers "always allow".
- Taint rule (LA9): after a sensitive read, outbound tools (`fetch_url`, `web_search`, MCP, external) ask for the rest of the turn. Tool output is untrusted and delimited before it re-enters the prompt (spotlighting, as Apple's own example does in `.historyTransform`).
- Never read the clipboard, the photo library or Files on a tool's own. Use pickers and the attachment flow.
- Permissions: ask nothing at launch. At the first call, show our own sheet ("AnyRouter wants to read your calendar to answer this") with Allow and Not now, and only Allow triggers the system prompt, since a denied system prompt cannot be asked again. A denied permission returns a plain tool error and an "Open Settings" row, with no retry. Sensitive tools are off by default. Ask for the least access: write-only for event creation, limited contacts with `ContactAccessButton`, approximate location. The first time a sensitive result would go to a cloud model, say so.
- Loop limits: 4 rounds on device and 8 on cloud, at most 2 calls per round, parallel only for reads, writes alone. Tool timeout 20 s, whole device turn 60 s. Stop on a repeated identical call. A rejected call returns a structured error (SwiftAgent's idea) and counts as a round. A pending write waits for the foreground and marks the turn "waiting for you". Steps are display only and not replayed (T3).

## Planned device tools

| Tool | API and access | Limit that shapes it |
|---|---|---|
| `ocr_image` | Vision `RecognizeDocumentsRequest`, none | on the chat's image attachments, on device |
| `calendar_search`, `reminders` | EventKit, full access | Verified: no read-only level. Write-only access cannot read even our own events. Event creation goes through `EKEventEditViewController` (the user's save is the confirmation). 20 results at most. |
| `contacts_lookup` | Contacts | Verified: users can grant a subset (iOS 18). |
| `place_search` | MapKit | search is region based |
| `weather` | WeatherKit | needs the capability on the App ID (operator), 500,000 calls a month, attribution required |
| `translate_text` | Translation `init(installedSource:target:)` | throws if languages are not installed: report it as a tool error |
| `run_shortcut` | `shortcuts://run-shortcut` | user-registered names only (no API lists shortcuts), leaves the app, text in and out, x-callback is Known. Wave 2. |
| Messages and Mail compose | MessageUI sheets | the user taps Send. Wave 2, write class. |
| Spotlight recall | CoreSpotlight over our own index | off by default, wave 2 (LA16) |

No tool for: Health (the app cannot tell a denied read from no data, and cloud use needs an App Review decision), Music, Notes (no public API), clipboard (the system notice fires when an app reads another app's content), Files and Photos (pickers instead). Settings > Integrations gets an "On this device" section with a switch and a status per tool.

## Siri, Shortcuts and App Intents

Works on iOS 26 with no entitlement: an `AskAnyRouterIntent(prompt:)` returning the answer, plus an `AppShortcutsProvider` whose phrases contain the app name (App Shortcut phrases embed only entity and enum parameters, so Siri asks for the prompt: Known). It shows in Shortcuts, Spotlight, the Action button and Siri, and Shortcuts can pass the result to "Use Model" (WWDC26 310). An intent has no chat UI, so only read tools run there, and a write needs `requestConfirmation` or is refused (LA12).

Not available: no assistant schema hands a free-form chat to a third-party app (`.assistant.activate` is Japan only, side button). The Siri AI route on iOS 27.3 (`@AppIntent(.tool)`, app skills) is a Developer Preview that does not work in App Store or external TestFlight builds, and adding any tool intent removes the App Shortcuts from Siri. Prototype it on an internal TestFlight build only, behind `#available(iOS 27.3, *)` (LA15).

## Foundation Models and local engines

- `Tool` (iOS 26.0) has `name`, `description`, `Arguments` and `call`. `@Generable` gives constrained output, and `GeneratedContent` with a dynamic schema is what `AppleDynamicTool` uses for MCP tools. Everything counts toward the window: instructions, tool definitions, arguments, outputs and replies.
- The window is 4,096 tokens in the guide. A WWDC26 sample prints 8,192 on the new model, so read `contextSize`, never hard-code. Exceeding it throws `LanguageModelError.contextSizeExceeded`, and recovery is a new session from a trimmed transcript. Private Cloud Compute has 32,000 tokens and needs a managed entitlement (iOS 27).
- No tool-calling accuracy numbers are published. Measure on our own prompts (LA11) and version prompts with `#available`, as Apple suggests. 26.4 and 27 improved tool calling.
- iOS 27 adds `DynamicProfile`, `.onToolCall` and `.historyTransform`, `ToolCallingMode` and the `LanguageModel` protocol. Rewriting history invalidates the KV cache, so append when you can. Apple's open source `ChatCompletionsLanguageModel` could back a session with AnyRouter, but needs the 27 SDK and we do not need it for our own loop.
- **MLX.** mlx-swift-lm has a `Tool/` module with parsers for Qwen 3.5, Gemma, Llama 3, Mistral, GLM 4, Kimi K2, MiniMax M2, Pythonic, Harmony and JSON, plus a `strict` validation mode. `MLXGuidedGeneration` constrains output by JSON Schema or EBNF. Small models call tools unreliably: use strict validation, at most 3 tools, short descriptions, and an eval pass before the switch.
- **GGUF.** llama.cpp's tool calling lives in `common/chat`, which our xcframework does not build (D14). Native formats cover Llama 3.x, Hermes and Qwen 2.5, Mistral Nemo, Functionary, DeepSeek R1 and GPT-OSS. Other templates use a costlier generic handler. GGUF needs that build or a Swift renderer and parser per family (T7). Do MLX first (Inferred).
- Core AI (iOS 27, `apple/coreai-models`) is out of this plan.

## Worth reading

foundation-models-utilities (history modifiers, skills; beta, needs 27 types). AnyLanguageModel (one tool interface across backends; too many dependencies to adopt). iMCP (which device tools people want and how to word them; macOS only). SwiftAgent (loop and structured rejection). We keep our own small MCP client (T1) over the swift-sdk.

## Sources

Apple: [Tool](https://developer.apple.com/documentation/foundationmodels/tool), [context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [DynamicProfile](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile), [Siri AI preview](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview), [assistant schema](https://developer.apple.com/documentation/appintents/app-schema-domain-assistant), [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [ContactAccessButton](https://developer.apple.com/documentation/contactsui/contactaccessbutton), [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [TranslationSession](https://developer.apple.com/documentation/translation/translationsession), [WeatherKit](https://developer.apple.com/weatherkit/), [Shortcuts URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios).
WWDC26: 241, 242, 347 (agentic security), 310 (Shortcuts), 343 and 344 (Siri).
Open source: [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), [foundation-models-utilities](https://github.com/apple/foundation-models-utilities), [llama.cpp function calling](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md), [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel), [iMCP](https://github.com/mattt/iMCP), [SwiftAgent](https://github.com/SwiftedMind/SwiftAgent).
