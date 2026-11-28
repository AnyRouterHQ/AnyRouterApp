import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct NotesLogicTests {
    @Test func aCallReplacesTheListWithTrimmedShortItems() throws {
        let long = String(repeating: "x", count: 300)
        let items = try NotesLogic.items(from: .object(["items": .array([.string(" Find the price "), .string(""), .number(3), .string(long)])]))
        #expect(items == ["Find the price", String(repeating: "x", count: NotesLogic.maxItemCharacters)])
        #expect(try NotesLogic.items(from: .object(["items": .array([])])) == [])
    }

    @Test func moreThanTenItemsOrNoListIsRefusedSoTheModelTriesAgain() {
        let eleven = JSONValue.object(["items": .array((1...11).map { JSONValue.string("step \($0)") })])
        #expect(throws: BuiltInToolError("At most 10 items. Merge or drop some.")) { try NotesLogic.items(from: eleven) }
        #expect(throws: BuiltInToolError("Missing the \"items\" list.")) { try NotesLogic.items(from: .object([:])) }
    }

    @Test func theModelReadsTheListBackAndALongRunRecitesIt() {
        #expect(NotesLogic.reply(["a", "b"]) == "Notes saved:\n1. a\n2. b")
        #expect(NotesLogic.reply([]) == "Notes cleared.")
        #expect(NotesLogic.recitation(["a"]) == "Your notes:\n1. a")
        #expect(NotesLogic.recitation([]) == nil)
    }
}

@MainActor
struct ChatNotesTests {
    @Test func theNotesStayOnTheChatAndADeletedChatHasNone() throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord()
        context.insert(thread)
        #expect(thread.notes.isEmpty && thread.notesData == nil)
        let notes = ChatNotes(context: context, thread: thread)
        #expect(try notes.replace(.object(["items": .array([.string("Find the price")])])) == "Notes saved:\n1. Find the price")
        #expect(thread.notes == ["Find the price"])
        #expect(notes.recitation == "Your notes:\n1. Find the price")
        _ = try notes.replace(.object(["items": .array([])]))
        #expect(thread.notesData == nil, "an empty list clears the data")
        thread.notesData = Data("nope".utf8)
        #expect(thread.notes.isEmpty)
        context.delete(thread)
        try context.save()
        #expect(notes.recitation == nil)
        #expect(throws: BuiltInToolError("The chat was deleted.")) { try notes.replace(.object(["items": .array([])])) }
    }
}

/// A read tool for the scripted runs.
private struct LookTool: BuiltInTool {
    let name = "look"
    let title = "Look"
    let summary = "Looks."
    let description = "Looks."
    let inputSchemaJSON = #"{"type":"object"}"#

    func run(_ arguments: JSONValue) async throws -> String { "looked" }
}

/// One scripted model round per request, keeping the rounds each request carried.
private final class NotesScript: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget? = nil
    private let lock = NSLock()
    private var scripts: [[StepEvent]]
    private var asked: [[AgentRound]] = []

    init(_ scripts: [[StepEvent]]) { self.scripts = scripts }

    var requests: [[AgentRound]] { lock.withLock { asked } }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let events = lock.withLock { () -> [StepEvent] in
            asked.append(rounds)
            return scripts.isEmpty ? [.end(finishReason: "stop")] : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// A cloud engine on the app's loop.
private struct CloudLoopEngine: ChatEngine {
    let source = ModelSource.anyrouter
    let model: ModelDescriptor
    let script: NotesScript

    func availableModels() async throws -> [ModelDescriptor] { [model] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AgentLoop.stream(step: script, host: tools, maxToolRounds: 8)
    }
}

/// G5: a long cloud run sees its notes after the last tool result of each round (agent design 4, "Todo recitation").
@MainActor
struct NotesRecitationChatTests {
    @Test func aFiveRoundCloudRunRecitesTheNotesAfterTheLastResultFromRoundThree() async throws {
        var model = testModel(id: "anyrouter/test", source: .anyrouter)
        model.capabilities.insert("tools")
        let notesCall = ToolCall(id: "n1", name: "notes", argumentsJSON: #"{"items":["Find the price","Write the answer"]}"#)
        let script = NotesScript([
            [.text("Plan first. "), .proposed(notesCall), .end(finishReason: "tool_calls")],
            [.proposed(ToolCall(id: "l1", name: "look", argumentsJSON: "{}")), .end(finishReason: "tool_calls")],
            [.proposed(ToolCall(id: "l2", name: "look", argumentsJSON: "{}")), .end(finishReason: "tool_calls")],
            [.proposed(ToolCall(id: "l3", name: "look", argumentsJSON: "{}")), .end(finishReason: "tool_calls")],
            [.text("Done."), .end(finishReason: "stop")],
        ])
        let registry = EngineRegistry()
        registry.register(CloudLoopEngine(model: model, script: script))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { toolContext in AgentToolHost(builtIns: toolContext.memoryTools + [LookTool()], search: nil, mcp: nil) })
        vm.input = "What does it cost?"
        await vm.send()?.value

        #expect(vm.thread?.notes == ["Find the price", "Write the answer"])
        let recitation = "\n\nYour notes:\n1. Find the price\n2. Write the answer"
        let lastResults = script.requests.map { $0.last?.results.last?.text }
        #expect(lastResults.count == 5)
        #expect(lastResults[0] == nil && lastResults[1] == "Notes saved:\n1. Find the price\n2. Write the answer", "rounds 1 and 2 recite nothing")
        for round in 2..<5 {
            #expect(lastResults[round] == "looked" + recitation, "round \(round + 1) has the notes after its last result")
            let earlier = script.requests[round].dropLast().flatMap(\.results).map(\.text)
            #expect(!earlier.contains { $0.contains("Your notes:") }, "only after the last result")
        }
        let stored = vm.messages.last?.toolSteps.compactMap(\.result?.text) ?? []
        #expect(stored.count == 4 && !stored.contains { $0.contains("Your notes:") }, "the reply keeps the results as they were")
    }
}
