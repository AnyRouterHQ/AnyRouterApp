import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// Prefix stability (agent v2 U5, agent design E2). Scripted chats record every request the model gets, and
/// `PrefixProbe` holds each request to the one before it. Every cache depends on a byte-stable prefix: the local KV cache
/// (U11), Apple's session (U15) and the provider caches behind AnyRouter (U16) each reuse a request only as far as it
/// repeats the one before it. A break is paid again on every turn, in seconds on a phone and in full-price input tokens
/// in the cloud.
///
/// Today's known breakers sit in `withKnownIssue` entries that name the unit that removes them (U6 to U8; U9 has
/// landed). When a unit lands, its entry records no issue, the test fails, and the unit deletes the entry.
///
/// Two U10 breakers are out of the probe's sight. JSON key order: the probe writes each object again with sorted keys,
/// since Swift orders a dictionary's keys by a seed taken from its storage address. The tool digest's localized words: the
/// app ships no translations and a test process cannot change its language, so the digest changes only across a relaunch
/// in another language. U10's golden tests cover both.
@MainActor
struct PrefixStabilityTests {
    // MARK: The probe

    private func data(_ text: String) -> Data { Data(text.utf8) }

    private func request(
        tools: String = "", system: String = "", messages: String, planned: PrefixProbe.PlannedBreak? = nil
    ) -> PrefixProbe.Request {
        PrefixProbe.Request(tools: data(tools), system: data(system), messages: data(messages), planned: planned)
    }

    @Test func aRequestThatStartsWithThePreviousOneKeepsIt() {
        #expect(PrefixProbe.firstDivergence(previous: data("abc"), next: data("abcdef")) == nil)
        #expect(PrefixProbe.firstDivergence(previous: data("abc"), next: data("abc")) == nil)
        #expect(PrefixProbe.firstDivergence(previous: Data(), next: data("a")) == nil)
    }

    @Test func theFirstChangedByteIsWhereACacheStopsReading() {
        #expect(PrefixProbe.firstDivergence(previous: data("abcdef"), next: data("abXdef")) == 2)
        #expect(PrefixProbe.firstDivergence(previous: data("abcdef"), next: data("abc")) == 3, "a shorter request lost the end")
    }

    /// Tools and the system message come first, so any change there, a tool added at the end included, moves every byte
    /// after it. Messages may only grow.
    @Test func toolsAndTheSystemMessageStayAndMessagesOnlyGrow() {
        let breaks = PrefixProbe.breaks([
            request(tools: "t", system: "s", messages: "a"),
            request(tools: "t", system: "s", messages: "ab"),
            request(tools: "tt", system: "s", messages: "ab"),
            request(tools: "tt", system: "S", messages: "ab"),
            request(tools: "tt", system: "S", messages: "aXc"),
        ])
        #expect(breaks == [
            PrefixProbe.Break(request: 2, part: .tools, offset: 1),
            PrefixProbe.Break(request: 3, part: .system, offset: 0),
            PrefixProbe.Break(request: 4, part: .messages, offset: 1),
        ])
        #expect(breaks.first?.description == "request 2 changed its tools at byte 1")
    }

    /// Clearing old results, compaction and dropping old photos start over on purpose, and the run's record says so.
    @Test func aBreakTheRunPlannedIsAllowedAndOnlyThatRequest() {
        for planned in PrefixProbe.PlannedBreak.allCases {
            let breaks = PrefixProbe.breaks([
                request(system: "s", messages: "old turns"),
                request(system: "s", messages: "summary", planned: planned),
                request(system: "s", messages: "summary and more"),
                request(system: "s", messages: "summary, cut"),
            ])
            #expect(breaks == [PrefixProbe.Break(request: 3, part: .messages, offset: 7)], "\(planned)")
        }
    }

    @Test func aCloudBodyReadsAsToolsThenSystemThenMessagesWithSortedKeys() throws {
        let body = #"{"temperature":0.7,"messages":[{"role":"system","content":"Be brief."},{"role":"user","content":"hi"}],"#
            + #""tools":[{"type":"function","function":{"name":"calc"}}],"stream":true}"#
        let request = try PrefixProbe.Request(cloudBody: data(body))
        #expect(String(decoding: request.tools, as: UTF8.self) == #"{"function":{"name":"calc"},"type":"function"}"# + "\n")
        #expect(String(decoding: request.system, as: UTF8.self) == #"{"content":"Be brief.","role":"system"}"# + "\n")
        #expect(String(decoding: request.messages, as: UTF8.self) == #"{"content":"hi","role":"user"}"# + "\n")
        let bare = try PrefixProbe.Request(cloudBody: data(#"{"messages":[]}"#))
        #expect(bare.tools.isEmpty && bare.system.isEmpty && bare.messages.isEmpty)
        #expect(throws: TestFailure.self) { _ = try PrefixProbe.Request(cloudBody: data("[]")) }
    }

    @Test func aLocalPromptReadsAsTheSystemPromptThenEachMessage() throws {
        let request = try PrefixProbe.Request(localSystem: nil, messages: [ChatMessage(role: .user, content: "hi")])
        #expect(request.tools.isEmpty && request.system.isEmpty)
        #expect(String(decoding: request.messages, as: UTF8.self) == #"{"content":"hi","role":"user"}"# + "\n")
        let prompted = try PrefixProbe.Request(localSystem: "Tools", messages: [])
        #expect(String(decoding: prompted.system, as: UTF8.self) == "Tools")
    }

    // MARK: Cloud chats

    /// The plain case every cache is built for: each turn only adds to the request before it.
    @Test func threePlainTurnsKeepThePrefix() async throws {
        let rig = try await CloudPrefixRig.make()
        for text in ["Hello", "Tell me more", "Thanks"] { await rig.send(text) }
        let requests = try rig.requests()
        #expect(requests.count == 3)
        #expect(PrefixProbe.breaks(requests).isEmpty)
    }

    /// A recalled memory rides in front of its own question only, so the next turn sends that question without it and
    /// every cache stops at the previous question.
    @Test func aRecallHitIsSentOnlyWithItsOwnQuestion() async throws {
        let rig = try await CloudPrefixRig.make()
        try rig.store.add("My dog is called Mochi", kind: .fact)
        await rig.send("What treats can Mochi eat?")
        await rig.send("Thanks")
        let requests = try rig.requests()
        #expect(requests.count == 2)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U6: recall hits go in front of the last question only, and the next request drops them") {
            #expect(breaks.filter { $0.part == .messages }.isEmpty)
        }
        #expect(breaks.filter { $0.part != .messages }.isEmpty)
    }

    /// A photo adds the attachment tools, and the tools come before everything else a provider caches.
    @Test func aPhotoInTheSecondTurnChangesTheToolList() async throws {
        let rig = try await CloudPrefixRig.make()
        defer { rig.temp.cleanup() }
        await rig.send("Hello")
        rig.vm.attachImages([(data: pngData(width: 64, height: 64), filename: "photo.png")])
        await rig.vm.finishIngesting()
        await rig.send("What is in this photo?")
        await rig.send("Thanks")
        let requests = try rig.requests()
        #expect(requests.count == 3)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U7: a photo adds read_attachment and ocr_image to the tool list") {
            #expect(breaks.filter { $0.part == .tools }.isEmpty)
        }
        #expect(breaks.filter { $0.part != .tools }.isEmpty, "the photo itself is sent with the same bytes every turn")
    }

    /// An @mention narrows one request to the named plugin. The turn before and the turn after pay for it twice.
    @Test func anAtMentionChangesOneRequestOnly() async throws {
        let rig = try await CloudPrefixRig.make()
        let exa = MentionItem(kind: .plugin(sourceID: "exa"), title: "Exa", trailing: "Plugin", icon: .asset("Logo-exa"))
        await rig.send("Hello")
        await rig.send("What is new in Swift?", mentioning: exa)
        await rig.send("Thanks")
        let requests = try rig.requests()
        #expect(requests.count == 3)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U7: an @mention keeps only the named plugin's tools and drops the skills index") {
            #expect(breaks.filter { $0.part != .messages }.isEmpty)
        }
        // No unit names this one yet. It is context on the last user message, like U6's, so U6 should store it too.
        withKnownIssue("U6: the @mention hint goes on the last question only, and the next request drops it") {
            #expect(breaks.filter { $0.part == .messages }.isEmpty)
        }
    }

    /// The profile sits in the system message, the start of every request.
    @Test func editingAProfileItemChangesTheSystemMessage() async throws {
        let rig = try await CloudPrefixRig.make()
        let item = try rig.store.add("Answer in short sentences.", kind: .preference)
        await rig.send("Hello")
        try rig.store.edit(item, text: "Answer in long sentences.")
        await rig.send("Tell me more")
        let requests = try rig.requests()
        #expect(requests.count == 2)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U8: the profile snapshot holds ids, so an edited item changes the system message at once") {
            #expect(breaks.filter { $0.part == .system }.isEmpty)
        }
        #expect(breaks.filter { $0.part != .system }.isEmpty)
    }

    /// Vietnamese text in the profile, the questions and a tool reply's digest keeps its bytes from turn to turn. The
    /// rounds of a tool run extend each other too.
    @Test func aVietnameseChatWithAToolReplyKeepsItsBytes() async throws {
        let rig = try await CloudPrefixRig.make()
        try rig.store.add("Trả lời bằng tiếng Việt.", kind: .preference)
        rig.script.then(.call(name: "calculator", arguments: #"{"expression":"2 + 2"}"#), .text("Bằng 4."))
        await rig.send("Tính giúp tôi 2 + 2")
        await rig.send("Cảm ơn bạn")
        await rig.send("Còn 3 + 3 thì sao?")
        let requests = try rig.requests()
        #expect(requests.count == 4)
        let breaks = PrefixProbe.breaks(requests)
        // No unit owns this break. History replays a tool reply as its text and tool digest (agent design 3.4), not as the
        // calls and results the last round sent, so the turn after any tool run starts over after its question.
        withKnownIssue("No unit yet: the turn after a tool run replaces the run's rounds with the reply and its digest") {
            #expect(breaks.filter { $0.request == 2 }.isEmpty)
        }
        #expect(breaks.filter { $0.request != 2 }.isEmpty)
    }

    // MARK: Local chats

    /// A local model reads its tools in the system prompt, so a tool list that follows the connection rewrites the start
    /// of the prompt, and the KV cache with it.
    @Test func goingOfflineChangesALocalModelsToolText() async throws {
        let rig = try await LocalPrefixRig.make(model: LocalPrefixRig.withTools)
        await rig.send("Hello there")
        rig.connection.isOnline = false
        await rig.send("Tell me more")
        rig.connection.isOnline = true
        await rig.send("Thanks")
        let requests = try rig.requests()
        #expect(requests.count == 3)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U7: offline leaves the web tools out of the tool list") {
            #expect(breaks.filter { $0.part == .system }.isEmpty)
        }
        #expect(breaks.filter { $0.part != .system }.isEmpty)
    }

    /// Three rounds: a call that fails, the same call again, and the round that must answer without tools. Each round
    /// re-reads the whole prompt when the start of it changes. U9 keeps the tool text in the last round's system prompt
    /// and asks for the answer at the end of its newest message, so this one holds.
    @Test func theForcedLastRoundOfALocalToolRunKeepsThePrefix() async throws {
        let rig = try await LocalPrefixRig.make(model: LocalPrefixRig.withTools)
        let call = ScriptedReply.call(name: "calculator", arguments: #"{"expression": "1 / 0"}"#)
        rig.script.then(call, call, .text("It cannot be divided by zero."))
        await rig.send("What is 1 / 0?")
        let requests = try rig.requests()
        #expect(requests.count == 3)
        let last = try #require(rig.prompts.entries.last)
        #expect(last.messages.last?.content.hasSuffix(LocalToolStep.answerNow) == true, "the third round is the forced one")
        #expect(PrefixProbe.breaks(requests).isEmpty)
    }

    /// Web results for a model without tools ride in front of their own question only.
    @Test func webResultsAreSentOnlyWithTheirOwnQuestion() async throws {
        let answer = ToolResult(
            callID: "search", name: "web_search_exa",
            text: "Title: Swift 7 ships\nURL: https://example.com/swift-7\nHighlights:\nSwift 7 is out with faster builds.", isError: false)
        let rig = try await LocalPrefixRig.make(
            model: LocalPrefixRig.withoutTools, search: PreSearcher(isOn: { _ in true }, search: { _, _ in answer }))
        await rig.send("What is the latest Swift news?")
        await rig.send("Thanks, that helps")
        let requests = try rig.requests()
        #expect(requests.count == 2)
        let breaks = PrefixProbe.breaks(requests)
        withKnownIssue("U6: web results go in front of the last question only, and the next request drops them") {
            #expect(breaks.filter { $0.part == .messages }.isEmpty)
        }
        #expect(breaks.filter { $0.part != .messages }.isEmpty)
    }
}

// MARK: Scripted chats

/// What the scripted model answers, one reply per request. Once the script runs out it answers "reply N".
private enum ScriptedReply: Sendable {
    case text(String)
    case call(name: String, arguments: String)

    /// The reply as an AnyRouter stream.
    func stream(number: Int) -> StubRegistry.Reply {
        let delta: [String: Any]
        let finish: String
        switch self {
        case .text(let text):
            delta = ["content": text]
            finish = "stop"
        case .call(let name, let arguments):
            let call: [String: Any] = [
                "index": 0, "id": "call_\(number)", "type": "function", "function": ["name": name, "arguments": arguments],
            ]
            delta = ["tool_calls": [call]]
            finish = "tool_calls"
        }
        let chunk = (try? JSONSerialization.data(withJSONObject: ["choices": [["delta": delta]]])) ?? Data()
        let events = [String(decoding: chunk, as: UTF8.self), #"{"choices":[{"delta":{},"finish_reason":"\#(finish)"}]}"#, "[DONE]"]
        return StubRegistry.Reply(body: Data(events.map { "data: \($0)\n\n" }.joined().utf8))
    }

    /// The reply as a Qwen-family local model writes it.
    var qwenText: String {
        switch self {
        case .text(let text): text
        case .call(let name, let arguments): "<tool_call>\n{\"name\": \"\(name)\", \"arguments\": \(arguments)}\n</tool_call>"
        }
    }
}

private final class ReplyScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ScriptedReply] = []

    func then(_ replies: ScriptedReply...) { lock.withLock { queue += replies } }

    func reply(to number: Int) -> ScriptedReply {
        lock.withLock { queue.isEmpty ? .text("reply \(number)") : queue.removeFirst() }
    }
}

/// Every request one test's model got, in order. Written off the main actor by the stub and the engine.
private final class RequestLog<Entry: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [Entry] = []

    var entries: [Entry] { lock.withLock { raw } }

    /// The entry's number, from 1.
    func record(_ entry: Entry) -> Int { lock.withLock { raw.append(entry); return raw.count } }
}

private struct AllowsEveryCall: ToolApproving {
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .allowOnce }
}

/// The app's own tool registry, so each request gets the tool list the app would build for it.
@MainActor
private func appToolRegistry() -> ToolRegistry {
    let defaults = testDefaults()
    let integrations = IntegrationsStore(
        defaults: defaults, credentials: FakeCredentialStore(), anyRouterToken: { nil }, session: MCPStubProtocol.session())
    return ToolRegistry(integrations: integrations, publicSources: ToolSourceCatalog.publicSources, defaults: defaults)
}

/// URLProtocol hands the body over as a stream.
private func bodyData(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

/// A chat with a tool-calling vision model on AnyRouter, behind a stubbed endpoint that records every request body.
@MainActor
private struct CloudPrefixRig {
    let vm: ChatViewModel
    let context: ModelContext
    let bodies: RequestLog<Data>
    let script: ReplyScript
    let temp: TempAttachments
    var store: MemoryStore { MemoryStore(context: context) }

    static func make() async throws -> CloudPrefixRig {
        let catalog = #"{"data":[{"id":"test/model","name":"Test","category":"text","capabilities":["chat","function-calling"],"#
            + #""architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}]}"#
        let bodies = RequestLog<Data>()
        let script = ReplyScript()
        let api = StubbedAPI { request in
            guard request.url?.path.hasSuffix("/chat/completions") == true else { return StubRegistry.Reply(body: Data(catalog.utf8)) }
            let number = bodies.record(bodyData(of: request))
            return script.reply(to: number).stream(number: number)
        }
        let temp = TempAttachments()
        let registry = EngineRegistry()
        registry.register(AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session, attachments: temp.store))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let tools = appToolRegistry()
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { tools.makeHost(approver: $0.approver ?? AllowsEveryCall(), context: $0) },
            isOnline: { true }, attachments: temp.store)
        vm.choose(try #require(models.models.first { $0.id == "anyrouter/test/model" }))
        return CloudPrefixRig(vm: vm, context: context, bodies: bodies, script: script, temp: temp)
    }

    func send(_ text: String, mentioning item: MentionItem? = nil) async {
        vm.input = text
        if let item { vm.addMention(item) }
        await vm.send()?.value
    }

    func requests() throws -> [PrefixProbe.Request] {
        try bodies.entries.map(PrefixProbe.Request.init(cloudBody:))
    }
}

/// What a local engine was asked: the system prompt and the messages, before the chat template.
private struct LocalPrompt: Sendable {
    let system: String?
    let messages: [ChatMessage]
}

/// A GGUF engine that writes what the script says and records every prompt it gets. The app wraps it in
/// `LocalToolEngine` as it does llama.cpp, so the tool rounds and the forced last round are the app's own.
private struct PromptRecordingEngine: ChatEngine {
    let models: [ModelDescriptor]
    let prompts: RequestLog<LocalPrompt>
    let script: ReplyScript

    var source: ModelSource { .gguf }

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        let number = prompts.record(LocalPrompt(system: params.systemPrompt, messages: messages))
        let text = script.reply(to: number).qwenText
        return AsyncThrowingStream { continuation in
            continuation.yield(.text(text))
            continuation.yield(.done(finishReason: "stop"))
            continuation.finish()
        }
    }
}

@MainActor
private final class OnlineSwitch {
    var isOnline = true
}

/// A chat with a local model on the app's tool loop and tool registry.
@MainActor
private struct LocalPrefixRig {
    /// "qwen" in the name gives it the Qwen tool format, so it gets tools.
    static let withTools = testModel(id: "gguf/qwen-3-probe", source: .gguf)
    /// No tool format: questions about now get a web search in front of them instead.
    static let withoutTools = testModel(id: "gguf/phi-probe", source: .gguf)

    let vm: ChatViewModel
    let prompts: RequestLog<LocalPrompt>
    let script: ReplyScript
    let connection: OnlineSwitch

    static func make(model: ModelDescriptor, search: PreSearcher = .none) async throws -> LocalPrefixRig {
        let prompts = RequestLog<LocalPrompt>()
        let script = ReplyScript()
        let registry = EngineRegistry()
        let base = PromptRecordingEngine(models: [withTools, withoutTools], prompts: prompts, script: script)
        registry.register(LocalToolEngine(wrapping: base, isEnabled: { true }))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let connection = OnlineSwitch()
        let tools = appToolRegistry()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { tools.makeHost(approver: $0.approver ?? AllowsEveryCall(), context: $0) },
            isOnline: { connection.isOnline },
            skipsToolsOffline: { tools.skipsOffline($0) },
            webSearch: search)
        vm.choose(try #require(models.models.first { $0.id == model.id }))
        return LocalPrefixRig(vm: vm, prompts: prompts, script: script, connection: connection)
    }

    func send(_ text: String) async {
        vm.input = text
        await vm.send()?.value
    }

    func requests() throws -> [PrefixProbe.Request] {
        try prompts.entries.map { try PrefixProbe.Request(localSystem: $0.system, messages: $0.messages) }
    }
}
