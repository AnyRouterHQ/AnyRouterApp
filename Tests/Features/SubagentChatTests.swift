import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// One scripted model round per request.
private final class ScriptedRounds: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget? = nil
    private let lock = NSLock()
    private var scripts: [[StepEvent]]

    init(_ scripts: [[StepEvent]]) { self.scripts = scripts }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let events = lock.withLock { scripts.isEmpty ? [StepEvent.end(finishReason: "stop")] : scripts.removeFirst() }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// An engine on the app's loop that can run subagents, and keeps what the chat and its subagent were offered.
private final class DelegatingEngine: SubagentEngine, @unchecked Sendable {
    let source: ModelSource
    let model: ModelDescriptor
    let parent: ScriptedRounds
    let child: ScriptedRounds
    private let lock = NSLock()
    private var offered: [[String]] = []
    private var children: [(messages: [String], prompt: String?, tools: [String])] = []

    init(model: ModelDescriptor, parent: ScriptedRounds, child: ScriptedRounds = ScriptedRounds([])) {
        source = model.source
        self.model = model
        self.parent = parent
        self.child = child
    }

    var parentTools: [[String]] { lock.withLock { offered } }
    var childRequests: [(messages: [String], prompt: String?, tools: [String])] { lock.withLock { children } }

    func availableModels() async throws -> [ModelDescriptor] { [model] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        lock.withLock { offered.append(tools?.specs.map(\.name) ?? []) }
        return AgentLoop.stream(step: parent, host: tools, maxToolRounds: 8)
    }

    func childStep(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, specs: [ToolSpec]) -> any StepFunction {
        lock.withLock { children.append((messages.map(\.content), params.systemPrompt, specs.map(\.name))) }
        return child
    }
}

/// `web_search` without a network.
private struct FakeSearch: BuiltInTool {
    let name = WebSearchBinding.name
    let title = "Search"
    let summary = "Searches."
    let description = "Searches."
    let schema: JSONSchema = #"{"type":"object"}"#

    func run(_ arguments: JSONValue) async throws -> String { "two results" }
}

private func toolModel(_ id: String, _ source: ModelSource) -> ModelDescriptor {
    var model = testModel(id: id, source: source)
    model.capabilities.insert("tools")
    return model
}

@MainActor
private func chat(_ engine: DelegatingEngine, search: Bool = true, subagents: Bool = true) async throws -> ChatViewModel {
    let registry = EngineRegistry()
    registry.register(engine)
    let models = ModelStore(registry: registry, defaults: testDefaults())
    await models.refresh()
    let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
    let web: [any BuiltInTool] = search ? [FakeSearch()] : []
    let vm = ChatViewModel(
        thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
        toolHost: { toolContext in AgentToolHost(builtIns: toolContext.memoryTools + web, search: nil, mcp: nil) })
    if !subagents { vm.subagentsEnabled = { false } }
    vm.input = "How do Swift actors work?"
    await vm.send()?.value
    return vm
}

private let delegation = ToolCall(
    id: "d1", name: SubagentLogic.toolName, argumentsJSON: #"{"task":"Find how Swift actors handle calls.","title":"Actors"}"#)

/// S1 in a chat: a cloud model hands research to a subagent; one collapsed row holds its steps; its spend counts in the
/// reply (PLAN D28, D25 unit 5).
@MainActor
struct SubagentChatTests {
    @Test func aCloudReplyShowsTheSubagentsStepsAsOneRowAndCountsWhatItSpent() async throws {
        let model = toolModel("anyrouter/test", .anyrouter)
        let child = ScriptedRounds([
            [.proposed(ToolCall(id: "s1", name: WebSearchBinding.name, argumentsJSON: #"{"query":"actors"}"#)),
             .usage(prompt: 100, completion: 10), .end(finishReason: "tool_calls")],
            [.proposed(ToolCall(id: "s2", name: WebSearchBinding.name, argumentsJSON: #"{"query":"actor isolation"}"#)),
             .usage(prompt: 200, completion: 20), .end(finishReason: "tool_calls")],
            [.text("Actors run one call at a time."), .usage(prompt: 300, completion: 30),
             .metadata(ResponseMetadata(costUSD: Decimal(string: "0.002"))), .end(finishReason: "stop")],
        ])
        let parent = ScriptedRounds([
            [.proposed(delegation), .usage(prompt: 1_000, completion: 50), .end(finishReason: "tool_calls")],
            [.text("They take one call at a time."), .usage(prompt: 1_200, completion: 40),
             .metadata(ResponseMetadata(costUSD: Decimal(string: "0.010"))), .end(finishReason: "stop")],
        ])
        let engine = DelegatingEngine(model: model, parent: parent, child: child)
        let vm = try await chat(engine)

        #expect(engine.parentTools.first?.contains(SubagentLogic.toolName) == true)
        let request = try #require(engine.childRequests.first)
        #expect(engine.childRequests.count == 1)
        #expect(request.messages == ["Find how Swift actors handle calls."], "the task only, not the chat")
        #expect(request.prompt == SubagentLogic.instructions)
        #expect(request.tools == [WebSearchBinding.name], "no notes, memory or other write tool")

        let reply = try #require(vm.messages.last)
        #expect(reply.content == "They take one call at a time.")
        let step = try #require(reply.toolSteps.first)
        #expect(reply.toolSteps.count == 1, "the subagent's calls are not rows of their own")
        #expect(step.result?.text == "Actors run one call at a time.")
        #expect(step.children?.map(\.id) == ["s1", "s2"])
        #expect(step.children?.allSatisfy { $0.result?.text == "two results" } == true)
        let subagent = try #require(SubagentLogic.make(step))
        #expect(SubagentLogic.heading(subagent) == "Subagent · Actors · 2 steps")
        #expect(ReplyParts.make(reasoning: nil, steps: reply.toolSteps, content: reply.content, isStreaming: false).map(\.id)
            == ["subagent-d1", "text"])

        let metadata = try #require(reply.metadata)
        #expect(metadata.costUSD == Decimal(string: "0.012"))
        #expect(metadata.promptTokens == 2_200 && metadata.completionTokens == 90, "the reply's own tokens")
        #expect(metadata.subagentPromptTokens == 600 && metadata.subagentCompletionTokens == 60)
        #expect((metadata.toolMs ?? 0) >= 0)
    }

    /// Device engines never spawn subagents, even one that could.
    @Test func aDeviceChatIsNeverOfferedTheSubagent() async throws {
        let engine = DelegatingEngine(model: toolModel("gguf/test/model.gguf", .gguf), parent: ScriptedRounds([[.text("Hi."), .end(finishReason: "stop")]]))
        _ = try await chat(engine)
        let offered = try #require(engine.parentTools.first)
        #expect(offered.contains(WebSearchBinding.name))
        #expect(!offered.contains(SubagentLogic.toolName))
        #expect(engine.childRequests.isEmpty)
    }

    /// The Subagents switch off in Settings: the cloud model works alone, with its web tools still there.
    @Test func theSettingsSwitchOffKeepsTheSubagentAway() async throws {
        let engine = DelegatingEngine(model: toolModel("anyrouter/test", .anyrouter), parent: ScriptedRounds([[.text("Hi."), .end(finishReason: "stop")]]))
        _ = try await chat(engine, subagents: false)
        let offered = try #require(engine.parentTools.first)
        #expect(offered.contains(WebSearchBinding.name))
        #expect(!offered.contains(SubagentLogic.toolName))
    }

    /// Without web search or the page reader (off, or offline) a subagent could not research, so it is not offered.
    @Test func aCloudChatWithoutAWebToolIsNotOfferedTheSubagent() async throws {
        let engine = DelegatingEngine(model: toolModel("anyrouter/test", .anyrouter), parent: ScriptedRounds([[.text("Hi."), .end(finishReason: "stop")]]))
        _ = try await chat(engine, search: false)
        let offered = try #require(engine.parentTools.first)
        #expect(offered.contains(NotesLogic.name))
        #expect(!offered.contains(SubagentLogic.toolName))
    }
}
