# Agent v2: context, caching, memory, camera, and a Swift core SDK

Date 2026-11-28. The plan for agent v2 and the Swift core SDK (PLAN D35). Units are ticked in PLAN.md as they land.

**Goal.** Make the app's agent much stronger on a phone. It should work well with tools, context and memory, reuse prompt caches on every engine, run local models well in 4K to 8K windows, take photos and live camera frames, and rest on one small Swift core SDK in the spirit of the Vercel AI SDK.

**How to read the labels.**
- [code] is a fact read in the code at the given file:line. Nothing was built or run for this plan.
- [doc] is what a primary source says.
- [meas] is a number someone measured, with the source given.
- [guess] is an inference to check before relying on it.
- Numbers in parentheses, like (14), point to the source list at the end.

Lanes: **A** is UI and CI runs. **B** is product features (agent, prompt, memory, cloud). **C** is engines and local inference. "Where it runs" names the check's home: CI unit test, model-smoke (GGUF on the Simulator CPU), the on-device list (MLX, Apple, camera, thermal), or live E2E (behind ANYROUTER_E2E_API_KEY).

## (a) Where the code stands

Paths are relative to AnyRouterApp/.

**Loop and runs.** Built and close to agent-design.md.
- AgentGraph is a pure transition table (Core/AgentGraph.swift:13-25). AgentLoop runs assemble, generate and act. Compact, approve and remember route to finish (Engines/Tools/AgentLoop.swift:178-180). Approval sits inside ToolHost.execute, and compaction runs before the reply in ChatViewModel. [code]
- Round caps: cloud 8 (AnyRouterEngine.swift:74), local 4 generations (LocalToolEngine.swift:8), subagent 4 requests and 30k tokens (SubagentLogic.swift:51-53). [code]
- Repeat detection covers only calls that already failed, matched on raw argument text (AgentLoop.swift:98,149-153). Calls in one round run one after another (:147-166). [code]
- Runs checkpoint and resume as designed (Core/AgentRun.swift, AgentRunSweep.swift, ChatViewModel.swift:754,1013-1035). E6 and E9 have tests. [code]

**Prompt assembly.** Partly built.
- PromptAssembler builds the system message from user instructions, profile and skills index (Features/Chat/PromptAssemblerLogic.swift:50). There is no app base prompt, so the system message is empty unless the user wrote instructions (InstructionsLogic.swift:27-33). [code]
- Recall hits, the device skill and web grounding are prepended to the last user message (PromptAssemblerLogic.swift:56-58). The next turn sends that message without them, so the prefix breaks at the previous user message every turn. [code]
- The cloud tools array changes with attachments, offline state, the memory switch and subagent availability (ToolRegistry.swift:249-274, SubagentTool.swift:15). The skills index drops on a turn with an @mention (ChatViewModel.swift:731). The profile snapshot freezes ids, not text (MemoryProfileLogic.swift:36-37). The tool digest uses localized strings (ToolDigestLogic.swift:12). [code]
- Local tool text joins the system prompt only when tools are on (LocalToolEngine.swift:122-124). The forced tools-off last round therefore changes the start of the prompt. [code]
- Token counting is one heuristic for every engine (TokenCountLogic.swift:8-36). Apple's tokenCount(for:) is unused. [code]

**Context limits.** Partly built.
- Tool results are clipped and old ones are stubbed as designed (RunBudgetLogic.swift:27-94). Error results are not protected from clearing, unlike design 3.4. [code]
- Compaction fires at a flat 80% of the window (CompactionLogic.swift:26,106-109), with no reserve and no 64k cloud cap. There is no compaction inside a run. GGUF also trims oldest turns by itself with a different reserve (GGUFEngine.swift:173-202). [code]
- MLX: CompactionLogic.window allows up to 8,192 tokens for MLX (CompactionLogic.swift:62), but MLXEngine uses a rotating KV cache of 4,096 (MLXEngine.swift:10,86). On an 8K plan the oldest tokens, the system prompt included, can rotate out. [code; effect is a guess]
- Apple's context length is hard-coded to 4096 (AppleFoundationEngine.swift:51). [code]

**Caching per engine.** Absent on device, implicit on cloud.
- GGUF creates a llama_context per generate call and frees it on exit (Engines/Local/GGUF/LlamaModel.swift:322-341). Every turn and every tool round re-decodes the whole prompt. There is no n_past carry-over and no llama_state_seq use. [code]
- MLX builds a new ChatSession per reply (MLXEngine.swift:85-92), so its KV cache is thrown away. [code]
- Apple builds a new LanguageModelSession per reply and replays history as text (AppleFoundationEngine.swift:93-94, ApplePrompt.swift:34-41). No prewarm. No usage is reported (:113). [code]
- AnyRouter sends no cache hints and no session id (AnyRouterEngine.swift:175-213). It reads cached tokens only from a custom metadata field (SSEParser.swift:169), not from usage.prompt_tokens_details. [code]

**Tools.** Built for cloud. Thin on device.
- Side-effect classes and approvals work (Core/Tools.swift:27-38, AgentToolHost.swift:76-82). Schemas are raw JSON strings (ToolSpec.inputSchemaJSON). [code]
- Local tool calls are free text with no grammar (LlamaModel.swift:391-402). Formats exist for Qwen, Gemma and Llama 3, picked by a substring of the model name (LocalToolFormat.swift:16-23). LFM, Inkling and MiniCPM get no tools. [code]
- Apple and local models get 4 tools, cut by a fixed order (ToolProfile.swift:13-43). [code]

**Memory.** Built, below its own target.
- BM25 with a relevance floor (MemoryRecallLogic.swift:24,66-118). The scripted eval asserts 9 of 13 recalled and 0 wrong (MemoryRecallEvalTests.swift:92-103). Design 5.3 asks for 0.9. [code]
- Embeddings can add at most one meaning-only hit (MemoryEmbeddingLogic.swift:46-50). The embedder is @MainActor and embeds up to 40 items on the send path (MemoryEmbeddings.swift:5,16). [code]
- No update or contradiction handling. The memory tool has no patch (ChatMemoryTools.swift:29-52). [code]

**Images and camera.**
- GGUF photos go through mtmd (VisionSession.swift:32-85). Only the last user message's photos count (GGUFEngine.swift:153-156). [code]
- **Bug.** A tool round appends a user message holding the results and no attachments (LocalToolEngine.swift:125-128). From round 2 the photo leaves the image path and the model sees only OCR text. [code]
- Photos are scaled and encoded again on every request (GGUFEngine.swift ImageProcessing.jpeg call). No bitmap id is set. [code]
- Cloud re-sends every earlier photo as base64 on every request (AnyRouterEngine.swift:217-231). [code]
- MLX and Apple take photos as OCR text only (ApplePrompt.swift:22). [code]
- The Decisions camera is a single shutter on the .photo preset (Features/Decisions/DecisionCameraView.swift:18,32). No frame sampler exists (R4 is a plan line). [code]

**Evals.** E1, E4, E6, E8, E9 and E10 have tests. E2, E5 and E7 are partial. E3 is missing. model-smoke runs the GGUF tool and memory evals nightly and never fails on model skill (AgentEvalSmokeTests.swift:7). Apple and MLX run by hand. There is no live cloud agent eval and no cache or image eval. The judge calls AnyRouter at temperature 0 (AgentEvalJudge.swift:89). The API serves deterministic requests from a 5-minute response cache (AnyRouter public docs), so a rerun inside 5 minutes can replay. [code; doc]

**The model contract.** ChatEngine has two stream overloads and ChatDelta carries text, reasoning, usage, done, toolCall, toolResult and metadata (Core/Contract.swift:48-75). Two extra protocols ride beside it, ResumableEngine (AgentLoop.swift:19) and SubagentEngine (SubagentTool.swift:6). Each engine owns its loop call. 61 of about 208 test files touch engine or step fakes. Core is a folder in the app target, and the coverage gate covers Core/* at 100%. [code]

## (b) Gaps, ranked by user impact

1. **Local replies re-read the whole prompt every turn and every tool round.** On a 4B model at 90 to 180 tok/s prefill on an A18 Pro (9) [meas for smaller models; 4B range is a guess], a 2k-token prompt costs 11 to 22 s before the first word, and a 3-round tool run pays it up to 4 times. This is the largest felt cost. (F3)
2. **The photo is lost after the first tool round.** A wrong answer about a photo the user just sent. Small fix.
3. **The prompt is not byte-stable.** Every cache depends on it: local KV reuse, Apple session reuse and provider caches. Today it breaks at the previous user message on every turn.
4. **Cloud input costs full price.** Cache reads bill at about 10% of input through AnyRouter (public docs) [doc], and sticky routing needs a session id the app does not send. Input is about 100 tokens per output token in agents (25) [meas].
5. **Local tool calls fail silently.** No grammar, only 3 families, and a name substring decides the format. Small models drop to near zero on multi-turn tool use below 4B (BFCL Qwen3-1.7B multi-turn 11.0, Llama-3.2-3B 4.0) (30) [meas].
6. **Long chats fail instead of shrinking.** No compaction inside a run, a flat 80% trigger, two trimmers that disagree, the MLX window mismatch, and Apple's hard-coded 4096 while iOS 27 gives 8,192 on newer devices (48) [doc].
7. **Apple sessions start cold every reply.** prewarm(promptPrefix:) exists (11) [doc]. Apple documents no cross-request KV reuse on iOS 26 [doc], so this needs an A/B before it counts.
8. **Memory misses meaning-only matches and never updates.** 9 of 13 recall against 0.9. A changed fact sits next to the old one. Negations retrieve alike under BM25 and embeddings (35) [meas].
9. **No live camera.** The operator wants it. Every piece exists in the frameworks, and none in the app.
10. **Cloud photos grow every request.** Every earlier photo is re-sent in full. A 1024x1024 photo costs about 1,369 tokens on Claude (37) [derived from doc].
11. **No agent eval checks caching, photos or the cloud loop.** Without it no unit above has a number.
12. **One contract with three side protocols.** Each engine owns its loop, so every unit above lands four times. This is the Core SDK's job.

## (c) The plan in small verifiable units

PLAN ids each unit replaces, so nobody builds a thing twice: U4 is S7, U11 is F3, U23 is LA10, U25 and U26 are T7 and LA14, U32 is R4, U35 is R3, U37 is L1 and LA11.

Order follows the evidence. Measure first. Fix bugs and prefix breakers next, because they need no new types. Then reshape the contract once, move each engine's cache into its new model type, and add features on top. Each unit ends in a named check. Lanes run in parallel where files do not overlap.

### Phase 0: measure, fix bugs, make the prefix stable

**U1 Usage ledger.** Lane B and C.
- Shape: struct Usage { input, cacheRead, cacheWrite, decoded, output, reasoning: Int; costUSD: Decimal? }. decoded is the tokens the engine actually prefilled. ChatDelta.usage carries it. One optional field on the reply record (part of Q8).
- Files: Core/Contract.swift, Engines/AnyRouter/SSEParser.swift:118-122, ResponseMetadata.swift, LlamaModel.swift (count decoded tokens), MLXEngine.swift (info.promptTokenCount), reply details sheet.
- Read usage.prompt_tokens_details.cached_tokens and top-level cache_creation_input_tokens, each defaulting to 0. Which upstreams report them through AnyRouter is not checked live yet. Show usage.cost when present.
- Check: CI unit tests on SSE fixtures with the fields present and absent. model-smoke prints decoded/prompt per turn for a 3-turn chat. Today's baseline should read 1.0 on every turn. That ratio is the baseline for U11. It is deterministic, unlike Simulator timings.

**U2 The photo stays in a tool run.** Lane C.
- Shape: images belong to the message they arrived on. The image path looks for the newest user message with attachments in the current turn, not the last user message.
- Files: Engines/Local/Tools/LocalToolEngine.swift:120-129, GGUFEngine.swift:153-156, VisionInput.swift:30-34.
- Check: CI unit test in LocalToolTests. Round 2 of a photo question still yields an ImageInput and the media marker.

**U3 Apple window from the system.** Lane C.
- Shape: contextLength = SystemLanguageModel.default.contextSize, back-deployed to 26.0 (13) [doc].
- Files: AppleFoundationEngine.swift:51.
- Check: CI unit test with an injected size. On-device list, an iOS 27 device on newer hardware reads 8,192.

**U4 MLX window equals its KV size.** Lane C.
- Shape: one number. MLX maxKVSize comes from the FitPlanner context, and CompactionLogic.window(mlx) returns the same number. Pin RotatingKVCache keep to the static prefix (10) [doc].
- Files: MLXEngine.swift:10,86, CompactionLogic.swift:62, FitPlanner.swift.
- Check: CI unit test that window(for: mlx model) is at most the KV size the engine is given.

**U5 Prefix probe (E2 made real).** Lane B.
- Shape: PrefixProbe.firstDivergence(previous: Data, next: Data) -> Int? over the encoded request. A scripted chat records every request.
- Scenarios: 3 plain turns, a recall hit, a photo added, offline toggled, an @mention, a 3-round tool run including the forced tools-off round, a profile edit, a Vietnamese locale.
- Rule: each request must extend the previous one up to the start of the newest exchange. Planned breaks are allowed and named: clearing old results (U20), compaction (U18), and dropping old photos at a compaction (U17). The probe takes the break event from the run record.
- Files: Tests/Features/PrefixStabilityTests.swift (new), RecordingEngine helpers.
- Check: CI unit test. Known breakers start as withKnownIssue entries, and U6 to U10 each remove one.

**U6 Injected context is stored on its message.** Lane B.
- Shape: MessageRecord.injectedContext: String? (Codable, default nil). Recall hits, grounding and the device skill are written once at send and replayed byte for byte. Compaction folds them like any turn.
- Files: PromptAssemblerLogic.swift:56-58, ChatViewModel.swift (send path near :733-835), Core records.
- Check: U5 recall and grounding scenarios pass. E1 stays green.

**U7 Tool list frozen per thread.** Lane B.
- Shape: ThreadRecord.toolSnapshot: [String], fixed order at first send. A tool that becomes unavailable stays listed and answers "Not available: offline" (Manus masks rather than removes (25) [doc]). New attachment tools append at the end. The skills index stays on @mention turns.
- Files: ToolRegistry.swift:249-274, SubagentTool.swift:15, ChatViewModel.swift:731.
- Check: U5 photo, offline and @mention scenarios pass. ToolSourceRegistryTests green.

**U8 Profile snapshot holds text.** Lane B.
- Shape: snapshot of rendered text. An edit applies from the next chat. Forget and Delete still apply now, because E10 and user intent win over one cache break.
- Files: MemoryProfileLogic.swift:32-43, MemoryProfileChatTests.swift:92.
- Check: U5 profile-edit scenario passes. E10 green.

**U9 Local tool block always present.** Lane C.
- Shape: the tool text stays in the system prompt on the forced last round. The tail says "Answer now without tools."
- Files: LocalToolEngine.swift:120-124, LocalToolFormat.swift.
- Check: U5 tool-run scenario passes on the local path. LocalToolTests green.

**U10 Fixed bytes: digest text and JSON key order.** Lane B.
- Shape: ToolDigestLogic renders a fixed English template, independent of locale and cost display. The request body and each tool schema serialize with sorted keys. Today the body is written without .sortedKeys (AnyRouterEngine.swift:208) and each schema is parsed into [String: Any] first (:236). Swift dictionary order follows a per-process hash seed, so the bytes can change after a relaunch, and U5 inside one test process cannot see it [code; the relaunch effect is a guess].
- Files: ToolDigestLogic.swift:9-14, ToolRowLogic.swift:26,36, AnyRouterEngine.swift:208,236.
- Check: CI tests. The digest bytes match under en and vi locales. The body bytes equal a golden file whose keys are sorted.

### Phase 1: reshape the contract (Core SDK phases K1 and K2, see below)

### Phase 2: each engine keeps its cache

**U11 GGUF keeps its context (F3).** Lane C. Lands inside K3 so LlamaModel.swift is touched once.
- Shape: struct KVLedger { tokens: [Int32]; spans: [ImageSpan] } with ImageSpan { start, count, nPos: Int; id: String }. Pure KVReuse.plan(cached:next:) -> .append(from:) | .trim(to:) | .reset.
- Steps, as llama-server does for each slot (1) [doc]: tokenize the full prompt, find the common prefix n, call llama_memory_seq_rm(mem, 0, n, -1), and on false clear the sequence and prefill all. Always decode at least one new token (2) [doc]. A trim never lands inside an image span (5) [doc].
- The context stays resident while the model is. Unload, memory warning and the 5-minute background unload free it too.
- Batch rule: a vision model's kept context is created with n_batch = n_ubatch = 1024. A photo needing more (Gemma 4 high budgets (52) [doc]) resets the context for that turn.
- Family classes, which decide the gain: dense (llama-3-2, qwen-3), sliding window (gemma-3, gemma-4), hybrid recurrent (qwen-3-5, lfm-3, lfm-3-vl), unknown (minicpm-5, inkling-2; read their GGUF headers). Partial trims can fail on hybrid and sliding-window models (3) [doc]. Pure appends still work on them [guess].
- Honest gain. The static prefix and all history before the newest exchange are reused. The newest exchange still prefills.
- Leave out per-thread KV files for v2. They cost about 115 to 150 MB per 1k tokens at f16 on 1.7B to 4B models [derived from configs], and upstream refuses state save for multimodal (4) [doc].
- Files: LlamaModel.swift:250-404, GGUFEngine.swift:170-210, LocalResidency.swift.
- Check: CI unit tests for KVReuse.plan, including the reset path and the image-span rule. model-smoke pinned to a dense family (llama-3-2 or qwen-3). The default "smallest GGUF" may be hybrid and would show no gain. Turns 2 and 3 must show decoded/prompt at most 0.35 against U1's 1.0, and greedy output must match a cold run. One hybrid run checks correctness only. ResidentModelsTests show unload frees the context.

**U12 History renders the same every time.** Lane C.
- Shape: the append law. render(turns[0..<n]) is a prefix of render(turns[0...n]) for every formatter.
- Rule for reasoning: past assistant turns render without reasoning, as Qwen3's template does (6) [doc]. A reply that had reasoning makes the next turn re-prefill from that reply's start, by trim on dense models and reset elsewhere. Thinking is off by default (F17), so this is rare.
- Files: Engines/Local/GGUF/PromptBuilder.swift:30-100, Jinja path in LlamaModel.swift:193-199.
- Check: CI golden tests of the append law for the Gemma 4, Inkling, ChatML, Llama 3 and Qwen3 Jinja renders.

**U13 One identity per image.** Lane C, with B for cloud.
- Shape: on ingest, store the exact scaled bytes per (attachment, side) with their sha256. The GGUF path calls mtmd_bitmap_set_id with that hash (5) [doc]. The ledger compares span ids. Cloud sends the same bytes every turn.
- Why now. Once U11 reuses KV, two photos with equal token counts would match by count alone, the way llama-server compares chunk ids (5) [doc]. This prevents that bug.
- Files: AttachmentIngest.swift, AttachmentStore, VisionSession.swift, AnyRouterEngine.swift:217-231.
- Check: CI unit test that two different photos never match in the ledger, and that the same photo gives identical bytes across turns. model-smoke counts mtmd encodes and expects none for a reused photo.

**U14 MLX keeps a session per thread.** Lane C.
- Shape: one ChatSession, or one [KVCache], per resident model and thread. ChatSession already diffs prompt tokens and trims or appends (10) [doc]. Dropped on model change, unload or compaction.
- Files: MLXEngine.swift:80-110, MLXConversation.swift.
- Check: CI unit test of the session key. On-device list for the numbers (the Simulator has no Metal for MLX). decoded/prompt from U1 on turns 2 and 3 is at most 0.35, against today's 1.0 measured first on the same device.

**U15 Apple keeps a session per chat and prewarms.** Lane C.
- Shape: AppleSessionCache keyed by (thread, instructions hash, tool names). A reused session gets only the new turn. A key change or compaction rebuilds it. Call prewarm(promptPrefix:) when the composer gets focus on an Apple chat (11) [doc]. Use tokenCount(for:) on 26.4 and later (13) [doc].
- Files: AppleFoundationEngine.swift:80-115, ApplePrompt.swift.
- Check: CI unit test that the key changes with tools or instructions. On-device A/B of 5 runs each, reused against fresh. Keep reuse only if median time to first token drops by more than twice the spread. Apple documents no KV reuse on 26 [doc].

**U16 Cloud cache hints.** Lane B.
- Shape: send session_id = thread id in the body. The router then prefers the upstream that served the last turn, to keep provider caches warm (19) [doc]. Place cache_control ephemeral on the last system part and the last message, for Anthropic-family models only (14) [doc]. Eval and judge calls send the documented skip-cache header.
- What to expect per provider. OpenAI caches on its own from 1,024 tokens, on an exact prefix that includes tool schemas (16) [doc]. Gemini 4 reuses the previous request only when the new one adds at least 2,050 tokens, so short tool rounds miss (17) [doc]. Anthropic needs breakpoints and a minimum of 512 to 4,096 tokens by model (14) [doc]. OpenRouter is the reference for how a gateway passes these through (18) [doc]. AnyRouter documents pass-through and bills reads at the provider's read rate (19) [doc].
- Caveat. Pass-through of cache_control for text and system parts is not verified, and Anthropic's own OpenAI-compatible layer drops caching (15) [doc]. Ship session_id first. Turn cache_control on only after the live check passes.
- Files: AnyRouterEngine.swift:175-213 (later a K2 middleware), AgentEvalJudge.swift:89.
- Check: CI request-body tests. Live E2E, two identical 2k-token requests to an Anthropic model and to an OpenAI model. The second must report cacheRead above 0.

**U17 Cloud photos within a budget.** Lane B.
- Shape: upload at most 1024 px on the long edge, and 768 for camera frames (37, 38, 39) [doc]. Old photos stay byte-identical (U13). They become their OCR text only at a compaction, because adding or removing images breaks Anthropic's message cache (14) [doc].
- Files: AnyRouterEngine.swift:217-231, AttachmentLogic.swift:10.
- Check: CI request-body test. Image bytes stay under the cap and are identical across turns.

### Phase 3: context and loop

**U18 One context budget.** Lane B.
- Shape: struct ContextBudget { window, reserve, trigger: Int }. reserve is the request's max output tokens. Local trigger 70% of window minus reserve, because compaction helped small models only when it left room (22) [meas on 1.2B and 9B; our threshold is a guess]. Cloud trigger is min(80%, 64k). Delete GGUF's own trim (GGUFEngine.swift:173-202).
- Files: CompactionLogic.swift, RunBudgetLogic.swift, GGUFEngine.swift.
- Check: new CI test for E3 (200 mixed English and Vietnamese turns on the Apple budget, every request fits, one summary). CompactionTests green.

**U19 Token counts from the model.** Lane B and C.
- Shape: LanguageModel.countTokens. GGUF and MLX use their tokenizer, Apple uses tokenCount(for:) on 26.4+, else the estimate. Cloud scales the estimate by the last real prompt_tokens over its estimate.
- Files: TokenCountLogic.swift:8-36, LlamaModel.swift (tokenize), MLXEngine.swift, AppleFoundationEngine.swift, AgentLoop.swift:129-130 (prompt_tokens already summed there).
- Check: CI test of the calibration. model-smoke reports the estimate's error on 20 fixed English and Vietnamese prompts.

**U20 Compaction inside a run, errors kept.** Lane B.
- Shape: the compact node runs inside the run when the next round will not fit. Masking runs first, then one summary. Masking alone cut cost 41 to 57% at equal solve rates on large models (20) [meas]. Error results are cleared last (25) [doc]. Anthropic calls result clearing the lightest safe form of compaction (23) [doc] and asks tools to truncate with a hint on how to narrow (24) [doc].
- Files: AgentLoop.swift:178-180 (Agent after K2), RunBudgetLogic.swift:50-94.
- Check: CI E4 extended. An error survives clearing, and an overflowing run compacts once and finishes.

**U21 Call fingerprints.** Lane B.
- Shape: fingerprint = name plus arguments re-encoded with sorted keys. The second identical call returns the earlier result with a note. The third stops the run with an answer. Repeated identical calls are the top small-model loop failure (31) [meas, practitioner report].
- Files: AgentLoop.swift:98,149-164.
- Check: CI E5 in full, including reordered JSON keys and a successful repeat.

**U22 A short app prompt.** Lane B.
- Shape: a static, versioned base prompt of at most 150 tokens on device. It covers tool use, notes and "get the date from the clock tool". No date or counter.
- Files: InstructionsLogic.swift:27-33, PromptAssemblerLogic.swift:50. Apple advises 1 to 3 paragraphs of instructions and 3 to 5 tools (12) [doc].
- Check: CI golden test. LA11 shows no drop against its baseline.

**U23 Tools picked per thread for device engines.** Lane B.
- Shape: at first send, a keyword and embedding match picks at most 4 tools from all enabled tools, in stable order. Re-pick only at compaction, which re-prefills anyway. Per-turn pruning helps small models (26, 27) [meas], but it would break the KV prefix every turn [guess, from the exact-prefix rule].
- Files: ToolProfile.swift:13-43, ToolRegistry.swift:272. Loading tool schemas just in time cut schema tokens about 9x for a 3B model on a phone (21) [meas].
- Check: L1 case set with 8 candidate tools, scored first on today's fixed-order 4-tool set as the baseline. The right tool is in the picked set for at least 90% of prompts and above the baseline.

**U24 Read calls run together (cloud).** Lane B.
- Shape: calls with sideEffect .read in one round run concurrently. Writes and external calls stay in order.
- Files: AgentLoop.swift:147-166, ToolRunScope (AppleToolRunLogic.swift:5).
- Check: CI test with gated fake tools. Two reads overlap and a write waits.

### Phase 4: local tool calls

**U25 Lazy grammar on the call envelope.** Lane C.
- Shape: GBNF.make(format:tools:) -> String, written by hand per format over a small schema subset (object, string, enum, number, integer, boolean, array). Use llama_sampler_init_grammar_lazy_patterns, which is in libllama at b12811 (2) [doc]. The JSON-schema converter lives in common/, which D14 excludes. The trigger is the family's call opener, so prose answers stay free (7) [doc].
- Default off. Hard constraints lowered small-model accuracy and abstention in two 2026 studies (28, 29) [meas]. Turn it on per family only after LA11 shows a gain at the shipped quantization.
- Files: LlamaModel.swift:391-402, new LocalToolGrammar.swift.
- Check: CI golden tests of the grammar text. model-smoke runs LA11 twice with and twice without. The valid-call rate must rise and abstention cases must not fall.

**U26 Formats from the template, plus LFM.** Lane C.
- Shape: detect the format from the GGUF chat template's tokens (tool_call tags, the LFM tool-call start token, python_tag) instead of the name. Add LFM's Pythonic call format.
- Files: LocalToolFormat.swift:16-23, LocalToolParser.swift.
- Check: CI parser tests with fixtures from the model cards. A detect test over the catalog families.

**U27 One repair try.** Lane B and C.
- Shape: a malformed call gets one retry with a specific error and the expected shape. A second failure answers without tools.
- Files: LocalToolParser.swift:36-120, AgentLoop.swift (Agent after K2).
- Check: CI unit test.

### Phase 5: memory

**U28 Rank fusion.** Lane B.
- Shape: reciprocal rank fusion with k = 60 over the BM25 and embedding rankings, keeping the floor and the cap of 3 [doc for RRF; this setup is a guess]. Add a negation trap pair to the eval set (35) [meas].
- Files: MemoryRecallLogic.swift:39-118, MemoryEmbeddingLogic.swift.
- Check: CI MemoryRecallEvalTests threshold rises from 9 to 12 of 13, with 0 wrong recalls.

**U29 Embed at write, off the main actor.** Lane B.
- Shape: the vector is computed when a memory is saved, off the main actor, and stored on the record. Recall only embeds the question.
- Files: OnDeviceEmbedder.swift:11-37, MemoryEmbeddings.swift.
- Check: CI test that a saved record has its vector. On-device list, measure today's recall p95 with 5,000 messages first, then require under 30 ms (design 5.3).

**U30 Slots replace old facts.** Lane B.
- Shape: MemoryRecord.slot: String? (for example "home city"), set by Apple extraction or the memory tool. A new fact in the same slot replaces the old one with Undo. The memory tool gains patch. Mem0 decides add, update, delete or nothing at write time (33) [doc]. Store a few keywords with each fact too. Fact-augmented keys raised recall about 9% in LongMemEval (34) [meas].
- Check: CI tests. "I moved to Hanoi" replaces "I live in Saigon". "I'm no longer vegetarian" replaces "I'm vegetarian".

**U31 Newest wins a tie.** Lane B.
- Shape: on equal score, the newer memory ranks first.
- Files: MemoryRecallLogic.swift:39-49.
- Check: CI eval pair with an outdated fact.

Embeddings through the AnyRouter API work with the sign-in key (public docs) [doc]. Under D28 they may only see memories scoped everywhere. That is a question for the operator, not a unit.

### Phase 6: photos and live camera

**U32 Live camera.** Lane B for the session, lane A for the screen and UI tests.
- Shape: struct CameraFrame { id: String; capturedAt: Date; pixelSize: CGSize; sharpness: Float; sceneDistance: Float; jpeg: Data }. struct FramePolicy { interval = 1 s; ring = 3; maxSide = 512 local, 768 cloud; sharpnessFloor; changeThreshold }. Pure FramePick.best(_ frames: [CameraFrame]) -> CameraFrame?.
- Behavior: AVCaptureVideoDataOutput samples about 1 frame a second into the ring. Sharpness is Laplacian variance (CPU, a few ms [doc, anecdotal]). Scene change is a feature-print distance, or a 32x32 thumbnail diff on the Simulator. A frame is sent only when the user asks, never from a free-running loop. Gemini Live caps at 1 frame a second (40) [doc], and the llama.cpp webcam demo skips a tick while a request runs (41) [doc]. thermalState at .serious pauses sampling. Thermal drops of 37 to 44% within minutes are reported for text-only MLX on an iPhone 16 Pro (45) [meas].
- Memory: Gemma 4 E4B peaked at 4,651 MB on an 8 GB iPhone with the increased memory limit and crashed without it (46) [meas]. Camera plus vision fits only small models on 6 GB devices [guess].
- Files: new Features/Camera/LiveCameraSession.swift and FramePickLogic.swift, Composer entry, Info.plist camera string exists for Decisions.
- Check: CI FramePickTests on synthetic frames (blurred against sharp, same scene against changed). On-device list, tap-to-first-token and peak memory with qwen-3-5 0.8B vision on a 6 GB-class device and with a cloud model.

**U33 Read text before sending pixels.** Lane B.
- Shape: RecognizeDocumentsRequest (iOS 26 (44) [doc]) runs on the chosen frame. For models without vision, or text-heavy frames, send the text alone.
- Files: AttachmentIngest.swift:33,156-167, VisionTextReader.
- Check: on-device eval of 10 photos (receipts, labels, screens). Accuracy and tokens per engine, image against text only.

**U34 Apple reads photos on iOS 27.** Lane C.
- Shape: behind #available(iOS 27) and the system's image-input support check (48) [doc]. iOS 26 keeps OCR text.
- Files: ApplePrompt.swift:22, AppleFoundationEngine.swift.
- Check: on-device list.

**U35 MLX vision (R3).** Lane C, after K3. FastVLM, LFM2-VL, SmolVLM2 and Qwen3-VL are in MLXVLM (42, 50) [doc]. Files: MLXEngine.swift, catalog vision fields. Check: on-device list.

**U36 Decisions uses the live camera.** Lane B. The Decisions shutter becomes U32's session with a capture button. Files: DecisionCameraView.swift:18,32, DecisionPhotoSection.swift:55. Check: DecisionsStoreTests green and a UI test of the capture path.

### Phase 7: evals

**U37 L1 finished.** Lane A.
- Shape: model-smoke writes one JSON report per run (case, engine, model, pass, rounds, decoded/prompt, cacheRead, tokens). A committed baseline file. A change counts only past twice the spread over 3 runs (PLAN's rule).
- Cases: LA11 per engine, abstention traps, a photo inside a tool run, U5 ratios, the cloud cache read (live E2E), and the U33 photo set (on-device).
- Check: the nightly run produces the report and compares it to the baseline.

### Choices the research settled

- **Sub-agents stay cloud only.** Multi-agent runs used about 15 times the tokens of chat (32) [meas]. On a phone the one resident model would queue a local sub-agent behind its parent. On cloud, delegate_task earns its place as a fresh-context reader of long pages that returns a short summary.
- **Device recall stays before the send, cloud keeps the tools.** Small models call search tools unreliably (30) [meas], so device engines get recall injected (U6). Cloud models keep memory and search_chats as tools, where an agent that chooses when to search did well (36) [meas, vendor result].
- **Local tool calling keeps the native template.** llama.cpp's own docs say native handlers beat the generic one and that heavy KV quantization can hurt tool calls (8) [doc]. U26 follows the template. S5's q4_0 KV option must pass LA11 before it ships.

## Core SDK

**Goal.** One small Swift core that every engine and caller goes through: one model protocol, one stream-part enum, typed tools, one agent loop with stop conditions and per-step preparation, and middleware. Caching, compaction and memory plug into named seams instead of four engines.

### What the research found

- **Vercel AI SDK 7** (47) [doc]. It has two layers.
  - The provider layer is one model call. LanguageModelV4 has doGenerate and doStream, with call options for prompt, sampling, tools, toolChoice, responseFormat, reasoning and providerOptions. providerOptions sits on every message and part, which is where cache breakpoints go.
  - The loop layer is streamText or ToolLoopAgent. It adds start-step, finish-step, tool-result, tool-error and approval parts.
  - Loop control is stopWhen (isStepCount, hasToolCall) and prepareStep, which may change model, activeTools, toolChoice, instructions and messages per step. Tools are values with inputSchema, execute, toolApproval and toModelOutput.
  - Middleware: wrapLanguageModel with transformParams, wrapGenerate and wrapStream. Built-ins include extractReasoningMiddleware and defaultSettingsMiddleware.
  - Usage: inputTokenDetails { noCache, cacheRead, cacheWrite } and outputTokenDetails { text, reasoning }.
- **Apple Foundation Models on iOS 27** (48) [doc]. The protocol is open. LanguageModel declares capabilities (guidedGeneration, reasoning, toolCalling, vision). A LanguageModelExecutor gets a generation request (transcript, enabled tool definitions, optional schema, options) and streams responses, reasoning and tool calls into a channel. The session runs the tools. Usage reports cached and reasoning tokens.
  - What it lacks: no tool approval API, no step-level stop conditions, no per-breakpoint cache control. Loop control is ToolCallingMode allowed, disallowed or required.
  - Every one of these types is iOS 27.0 or later. So is PrivateCloudComputeLanguageModel (32K context, reasoning levels, an entitlement, and daily per-user quotas) (48) [doc].
  - apple/foundation-models-utilities ships a ChatCompletionsLanguageModel for OpenAI-style servers, iOS 27 only (49) [doc].
- **Swift ports** [doc, from the repos].
  - huggingface/AnyLanguageModel (50) mirrors Apple's API back to iOS 17 and covers Foundation Models, MLX, llama.cpp and cloud providers. Each model runs its own tool loop, which would lose our run records, approvals and resume.
  - teunlao/swift-ai-sdk (51) ports the Vercel SDK at spec V4 with ToolLoopAgent, approvals and middleware, but has no on-device provider.
  - mlx-swift-lm has the best local tool-call parsers (many families, recovery policies) (50) [doc]. Borrow its ideas for U26.
  - No package combines step control, approvals, middleware and on-device engines.

### Two options

| | A. Apple's LanguageModel as the spine | B. Our own protocol, shaped like the AI SDK |
|---|---|---|
| iOS 26 floor (D5) | Cannot compile against it. Needs a clone such as AnyLanguageModel, plus #available everywhere | Works on 26 |
| Loop control | Session-owned loop. No approvals, no prepareStep, no stop conditions | Ours. It keeps run records, approvals and resume (D28) |
| Caching | The provider manages it from transcript diffs. No breakpoints | Explicit. A ledger per engine plus cloud breakpoints |
| Gets for free | @Generable, the transcript, PCC, iOS 27 images | Nothing free. Most of it exists in AgentLoop already |
| Cost | Rewrite the loop on Apple's terms, and lose features | Evolve today's StepEvent and ChatDelta |

**Recommendation: B.**
- The deciding constraint is D5. Every Apple custom-model API is iOS 27 only.
- Our loop already does what Apple's lacks: approvals, resume and per-step budgets.
- On iOS 27, Apple's models become providers inside B through thin #available adapters. B's one-call layer maps directly onto an Apple executor-style request, so the adapter stays small.
- Plugging our models into Apple's session (the reverse adapter) buys only Apple's loop, which we replace. It is not planned.
- Raising the floor to iOS 27 is an operator question (Q1 below). It would not change the recommendation, only remove the #available checks.

### Types (signatures only)

Shape rule: evolve, do not invent. StepEvent becomes ModelPart, the provider layer. ChatDelta becomes AgentPart, the loop layer. ToolHost stays as the executor.

    // Core/Agent/ModelContract.swift
    // Names avoid FoundationModels' Prompt (iOS 26) and LanguageModel (iOS 27), which the Apple engine also imports.
    protocol ModelProvider: Sendable {
        var source: ModelSource { get }
        func models() async throws -> [ModelDescriptor]
        func model(for descriptor: ModelDescriptor) throws -> any ChatModel
    }
    protocol ChatModel: Sendable {
        var descriptor: ModelDescriptor { get }
        var traits: ModelTraits { get }
        func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelPart, any Error>
        func countTokens(_ prompt: ModelPrompt, tools: [ToolDefinition]) async -> Int
        func prewarm(_ prompt: ModelPrompt, tools: [ToolDefinition]) async       // default: no-op
    }
    struct ModelTraits: Sendable, Equatable {
        var window: Int
        var tools: ToolCalling          // .none, .native, .text(LocalToolFormat), .framework
        var vision: VisionLimits?       // maxImages, imageSide
        var cache: CacheStyle           // .none, .kvLedger, .session, .provider
    }
    struct ModelRequest: Sendable {
        var prompt: ModelPrompt
        var tools: [ToolDefinition]
        var toolChoice: ToolChoice      // .auto, .none, .required, .named(String)
        var settings: CallSettings      // temperature, topP, maxOutputTokens, reasoning, stop
        var output: OutputFormat        // .text, .json(JSONSchema)
        var cache: CacheHints           // sessionID, breakpoints: [PromptAnchor]
    }
    struct ModelPrompt: Sendable, Hashable { var instructions: [String]; var messages: [ModelMessage] }
    struct ModelMessage: Sendable, Hashable, Codable { var role: Role; var parts: [Part] }   // user, assistant, tool
    enum Part: Sendable, Hashable, Codable {     // wraps today's stored ToolCall and ToolResult unchanged
        case text(String), image(ImageRef), file(FileRef), reasoning(String)
        case toolCall(ToolCall), toolResult(ToolResult)
    }
    struct ImageRef: Sendable, Hashable, Codable { var attachmentID: UUID; var sha256: String; var side: Int }
    enum ModelPart: Sendable {
        case text(String), reasoning(String)
        case toolInputStart(id: String, name: String), toolCall(ToolCall)
        case toolResult(ToolResult)     // only from .framework models (Apple runs its own tools)
        case usage(Usage), metadata(ResponseMetadata), finish(FinishReason)
    }

    // Core/Agent/ToolDefinitions.swift (Core/Tools.swift exists; file names must be unique)
    struct ToolDefinition: Sendable, Hashable, Codable {
        var name: String; var description: String; var schema: JSONSchema; var sideEffect: ToolSideEffect
    }
    indirect enum JSONSchema: Sendable, Hashable, Codable {   // replaces inputSchemaJSON and ToolSchemaNode
        struct Property: Sendable, Hashable, Codable { var name: String; var schema: JSONSchema }
        case object([Property], required: [String])
        case string(oneOf: [String]?), number, integer, boolean, array(JSONSchema)
    }
    protocol ToolExecutor: Sendable {                         // today's ToolHost, approval inside
        var definitions: [ToolDefinition] { get }
        func execute(_ call: ToolCall) async -> ToolResult
    }

    // Core/Agent/AgentRunner.swift
    enum AgentPart: Sendable {
        case model(ModelPart), stepStarted(Int), toolResult(ToolResult)
        case approval(ToolStep), stepFinished(StepRecord), finished(RunOutcome)
    }
    struct StopCondition: Sendable {
        let reason: @Sendable (RunState) -> StopReason?
        static func steps(_ n: Int) -> StopCondition
        static func tokenBudget(_ n: Int) -> StopCondition
        static func repeatedCall(limit: Int) -> StopCondition
    }
    protocol StepPreparing: Sendable {                        // prepareStep
        func plan(_ state: RunState) async throws -> ModelRequest
    }
    protocol ModelMiddleware: Sendable {
        func request(_ request: ModelRequest, model: ModelDescriptor) async throws -> ModelRequest
        func stream(_ parts: AsyncThrowingStream<ModelPart, any Error>, request: ModelRequest)
            -> AsyncThrowingStream<ModelPart, any Error>
    }
    protocol RunCheckpointing: Sendable { func save(_ state: RunState) async }
    struct Agent: Sendable {
        init(model: any ChatModel, prepare: any StepPreparing, tools: any ToolExecutor,
             stop: [StopCondition], middleware: [any ModelMiddleware], checkpoint: any RunCheckpointing)
        func run(resuming: AgentResume?) -> AsyncThrowingStream<AgentPart, any Error>
    }

**Where the v2 units plug in.**
- StepPreparing (ChatStepPreparer) holds PromptAssembler, recall at step 0 (U6), clearing and in-run compaction (U20), the thread's tool set (U23) and notes recitation.
- StopCondition holds the round caps, the subagent token budget and fingerprints (U21).
- Middleware holds telemetry (usage and timing, never prompts), CloudCacheMiddleware (U16), PrivacyMiddleware (asserts no deviceOnly memory in a cloud request, which is E8 enforced at run time) and ReasoningSplitMiddleware (today's ReasoningSplitter).
- Each model holds its own cache. The GGUF and MLX models keep the ledger (U11, U14), and AppleModel keeps the session cache (U15). The local tool text format stays inside the local model, because it shapes the prompt the ledger caches.
- AppleModel declares tools: .framework. The Agent then forwards the executor and does not run tools itself. That is today's behavior, made explicit.

**Folder or package.** Default is a folder, Core/Agent/, in the app target.
- It needs no public types, no new imports, and no coverage-gate change. Core/* is already gated at 100%.
- A package (Packages/AgentCore) pays for itself only when F23's Linux job exists. Then the pure core (types, Agent, PromptAssembler, budgets, recall) could run swift test on Linux. macOS minutes cost 10x.
- That condition is the trigger. Until then the cost is public types, imports in about 60 test files, and a gate script change, for no gain.

### Migration phases

Each phase moves its callers and deletes the old path in the same wave. There is no standing adapter.

**K1 Reshape the contract in place.** Lane B, with C reviewing engines. Three mechanical waves, each green on its own, each done by a script (a codemod over the 17 test engines and ScriptedEngine). No behavior change.
- K1a Schema and usage. ToolSpec.inputSchemaJSON becomes JSONSchema with sorted-key encoding, and ToolSchemaNode is deleted. Usage gains the cache fields (U1). Check: new JSONSchemaTests (round trip, sorted keys), AppleToolTests green.
- K1b Message parts. ChatMessage becomes ModelMessage with parts. Part wraps the stored ToolCall and ToolResult types unchanged, because reply JSON and AgentRunState are stored and must still decode (PLAN Contract). Check: fixtures written by today's build (a reply with tool steps, a saved awaitingApproval run) decode after the change.
- K1c Provider and model split. ChatEngine becomes ModelProvider plus ChatModel. All four engines and the side callers move: TitleGenerator.swift:14, ChatSummaries.swift:33, ChatViewModel.swift:286, HeadlessChat.swift:55. Deleted: the two stream overloads and their default, ChatDelta (replaced by ModelPart), the string capabilities. Check: every existing CI test green, plus ScriptedModel tests.

**K2 One loop.** Lane B.
- AgentLoop becomes Agent with StepPreparing, StopCondition and middleware. AnyRouterStep and LocalToolStep fold into their models' stream.
- Deleted: StepFunction, StepEvent, ResumableEngine, SubagentEngine, AgentLoop.continuing, the LocalToolEngine wrapper, the as? ResumableEngine cast (ChatViewModel.swift:946-958). ToolRunScope moves out of Engines/Apple.
- Check: AgentLoopTests, AgentLoopScenarioTests, AnyRouterToolLoopTests, SubagentRunTests and AgentResumeChatTests green on the new types. New AgentTests for stop conditions and middleware order. U5 green on all scripted paths.

**K3 Local models hold their caches.** Lane C. U11, U12, U13 and U14 land here, so LlamaModel.swift and MLXEngine.swift are touched once.
- Check: the U11 and U13 tests and their model-smoke numbers. GGUFModelSmokeTests green.

**K4 Apple model.** Lane C. U15, plus #available(iOS 27) adapters for the 8K system model and images (U34). The PCC provider waits for Q2.
- Check: AppleToolTests green. U15's A/B on the on-device list.

**K5 Cleanup.** Lane B. Delete leftovers the compiler names. Update agent-design.md and PLAN D28 (one new decision line: "Core SDK, option B").
- Check: rg finds no ChatEngine, StepFunction or ChatDelta. scripts/source-check.sh and CI green.

## Questions for the operator

Answers so far (2026-11-28): Q2 yes, built as D34 (lane C). Q4 yes, U25 stays off until LA11 shows a gain. Q1 and Q3 are open, so nothing that depends on them is built.

- **Q1.** Raise the floor to iOS 27 (shipped September 2026)? It removes #available checks and opens Apple images, the 8K window and PCC. It drops iOS 26 devices.
- **Q2.** Add Apple's Private Cloud Compute model as a provider? It is 32K, with no account and Apple's privacy terms (48) [doc]. It would change X1 escalation and the D28 rule on what leaves the device.
- **Q3.** May memories scoped everywhere use AnyRouter embeddings for cloud chats? deviceOnly items never would.
- **Q4.** Local grammar (U25) stays off by default until LA11 shows a gain. Agree?

## Conflicts and gaps in the research

- 4B prefill on an iPhone 16 Pro: about 180 tok/s interpolated from llama.cpp numbers (9) [guess] against 92 tok/s on a site that labels its figure an estimate. Measure with U1 on a device.
- No published iPhone time for an mmproj encode. The nearest is LFM2.5-VL-450M on an Android phone: 182 ms GPU for a 210-token image, 1.6 s for 1,795 tokens (43) [meas]. One 512 px tile is the default for that reason.
- Whether partial-trim fixes for hybrid models are in b12811 is unknown (3). U11 treats a failed trim as reset.
- Apple documents no KV reuse across requests on iOS 26. U15 is an experiment with a keep-or-drop rule.
- cache_control pass-through for text parts through AnyRouter is unverified (no live call yet). U16 gates it on a live check.
- The 2026 arXiv results (20, 22, 28, 29) were read from abstracts or summaries. They set defaults and thresholds that U22, U25 and U18 must confirm on our evals.

## Sources

1. llama.cpp server README: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
2. llama.h (seq_rm, state_seq, grammar samplers): https://github.com/ggml-org/llama.cpp/blob/master/include/llama.h
3. Hybrid models re-process every turn: https://github.com/ggml-org/llama.cpp/issues/24714
4. Slot save refused for multimodal: https://github.com/ggml-org/llama.cpp/issues/19466
5. mtmd.h (bitmap ids, chunks): https://github.com/ggml-org/llama.cpp/blob/master/tools/mtmd/mtmd.h
6. Qwen3 chat template: https://huggingface.co/Qwen/Qwen3-4B/raw/main/tokenizer_config.json
7. Lazy grammars: https://github.com/ggml-org/llama.cpp/pull/12034
8. llama.cpp function calling: https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md
9. iPhone llama.cpp benchmarks: https://github.com/ggml-org/llama.cpp/discussions/4508
10. mlx-swift-lm ChatSession and KVCache: https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLMCommon/ChatSession.swift
11. prewarm(promptPrefix:): https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)
12. TN3193 context window: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
13. contextSize and tokenCount(for:): https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize
14. Anthropic prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
15. Anthropic OpenAI SDK compatibility: https://platform.claude.com/docs/en/api/openai-sdk
16. OpenAI prompt caching: https://developers.openai.com/api/docs/guides/prompt-caching
17. Gemini caching: https://aistudio.google.com/docs/caching
18. OpenRouter prompt caching: https://openrouter.ai/docs/guides/best-practices/prompt-caching
19. AnyRouter API docs (caching, sessions, embeddings): https://anyrouter.dev/docs
20. The Complexity Trap: https://arxiv.org/abs/2508.21433
21. Adaptive context management on device: https://arxiv.org/abs/2511.03728
22. ContextCompact: https://arxiv.org/abs/2610.25516
23. Anthropic context engineering: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
24. Anthropic writing tools: https://www.anthropic.com/engineering/writing-tools-for-agents
25. Manus context engineering: https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus
26. Less is More, tool selection: https://arxiv.org/abs/2411.15399
27. RAG-MCP: https://arxiv.org/abs/2505.03275
28. The Constraint Tax: https://www.alphaxiv.org/abs/2605.26128
29. Repair, Not Improvement: https://arxiv.org/abs/2608.13959
30. BFCL leaderboard data: https://gorilla.cs.berkeley.edu/data_overall.csv
31. Local agent loop failure modes: https://dev.to/thlandgraf/four-failure-modes-youll-hit-running-a-local-llm-in-a-multi-step-agentic-loop-3kd9
32. Anthropic multi-agent research: https://www.anthropic.com/engineering/multi-agent-research-system
33. Mem0: https://arxiv.org/abs/2504.19413
34. LongMemEval: https://arxiv.org/abs/2410.10813
35. NevIR, negation in retrieval: https://arxiv.org/abs/2305.07614
36. Letta memory benchmark: https://www.letta.com/blog/benchmarking-ai-agent-memory
37. Claude vision token rules: https://platform.claude.com/docs/en/build-with-claude/vision
38. Gemini media resolution: https://aistudio.google.com/docs/media-resolution
39. OpenAI image inputs: https://developers.openai.com/api/docs/guides/images-vision
40. Gemini Live: https://aistudio.google.com/docs/live-guide
41. llama.cpp realtime webcam demo: https://github.com/ngxson/smolvlm-realtime-webcam
42. FastVLM: https://machinelearning.apple.com/research/fast-vision-language-models
43. LFM2.5-VL timings on Android: https://github.com/hyeons-lab/cera/pull/483
44. Vision RecognizeDocumentsRequest (WWDC25 272): https://developer.apple.com/videos/play/wwdc2025/272/
45. iPhone thermal study: https://arxiv.org/abs/2603.23640
46. Increased memory limit data point: https://zenn.dev/mtfum/articles/ios_memory_entitlements
47. Vercel AI SDK (spec V4, migration to 7): https://github.com/vercel/ai
48. Apple LanguageModel and WWDC26 241, 242, 319, 339: https://developer.apple.com/documentation/foundationmodels/languagemodel and https://developer.apple.com/videos/play/wwdc2026/339/
49. apple/foundation-models-utilities: https://github.com/apple/foundation-models-utilities
50. AnyLanguageModel: https://github.com/huggingface/AnyLanguageModel and mlx-swift-lm: https://github.com/ml-explore/mlx-swift-lm
51. swift-ai-sdk: https://github.com/teunlao/swift-ai-sdk
52. Gemma 4 image batch note: https://dev.to/someoddcodeguy/a-quick-note-on-gemma-4-image-settings-in-llamacpp-39ng
