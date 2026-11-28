import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// How many times the tool body itself ran.
private final class LocalToolRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = 0
    var value: Int { lock.withLock { raw } }
    func add() { lock.withLock { raw += 1 } }
}

/// A tool that acts outside the app, so it asks every time.
private struct LocalNoteTool: BuiltInTool {
    let runs: LocalToolRuns
    let name = "send_note"
    let title = "Send note"
    let summary = "Sends a note."
    let description = "Sends a note."
    let inputSchemaJSON = #"{"type":"object"}"#
    let sideEffect = ToolSideEffect.external

    func run(_ arguments: JSONValue) async throws -> String {
        runs.add()
        return "sent"
    }
}

/// The text a model writes for each generation, and the messages each generation was asked with.
private final class LocalReplies: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private var asked: [[ChatMessage]] = []

    init(_ replies: [String]) { self.replies = replies }

    var requests: [[ChatMessage]] { lock.withLock { asked } }

    func next(_ messages: [ChatMessage]) -> String {
        lock.withLock {
            asked.append(messages)
            return replies.isEmpty ? "done" : replies.removeFirst()
        }
    }
}

private let resumeQwen = ModelDescriptor(
    id: "gguf/unsloth/Qwen3.5-4B-GGUF/q4.gguf", source: .gguf, displayName: "Qwen 3.5 4B", contextLength: nil,
    capabilities: ["chat"], sizeBytes: nil, isInstalled: true)

/// A llama.cpp engine that only writes text. `LocalToolEngine` around it gives it the app's tool loop.
private struct LocalTextEngine: ChatEngine {
    let source = ModelSource.gguf
    let script: LocalReplies

    func availableModels() async throws -> [ModelDescriptor] { [resumeQwen] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        let text = script.next(messages)
        return AsyncThrowingStream { continuation in
            continuation.yield(.text(text))
            continuation.yield(.done(finishReason: "stop"))
            continuation.finish()
        }
    }
}

/// G4 for a model on this device: a run that waits for approval survives the app being killed, on the same loop the
/// AnyRouter engine uses (agent design 1.3, evals E6 and E9).
@MainActor
struct LocalResumeChatTests {
    private let call = ToolCall(id: "c1", name: "send_note", argumentsJSON: "{}")
    private let written = "Sending. " + #"<tool_call>{"name": "send_note", "arguments": {}}</tool_call>"#

    private func storeURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "chats.store")
    }

    /// One app launch on the store at `url`: the launch sweep, then a chat screen's view model on `threadID`.
    private func launch(
        replies: [String], url: URL, thread threadID: UUID?, runs: LocalToolRuns, approver: ToolApprovalCenter,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> (vm: ChatViewModel, context: ModelContext, script: LocalReplies) {
        let script = LocalReplies(replies)
        let registry = EngineRegistry()
        registry.register(LocalToolEngine(wrapping: LocalTextEngine(script: script), isEnabled: { true }, makeID: { "c1" }))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        AgentRunSweep.run(context)
        let thread = try threadID.flatMap { id in
            try context.fetch(FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })).first
        }
        let vm = ChatViewModel(
            thread: thread, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { toolContext in
                AgentToolHost(builtIns: [LocalNoteTool(runs: runs)], search: nil, mcp: nil, approver: toolContext.approver)
            },
            approver: approver, save: save)
        return (vm, context, script)
    }

    /// A first launch that asks for `send_note` and waits on its card, killed there; then a second launch on the same
    /// store with the card back. The caller answers it.
    private func relaunchedOnTheWaitingCard(
        after answer: String, runs: LocalToolRuns
    ) async throws -> (vm: ChatViewModel, context: ModelContext, script: LocalReplies, center: ToolApprovalCenter, replyID: UUID) {
        let url = try storeURL()
        let alive = Flag()
        alive.value = true
        let firstCenter = ToolApprovalCenter()
        let before = try await launch(
            replies: [written], url: url, thread: nil, runs: runs, approver: firstCenter, save: { if alive.value { try $0.save() } })
        before.vm.input = "Send the note"
        _ = try #require(before.vm.send())
        #expect(await waitUntil { firstCenter.pending?.request.call.id == "c1" && before.vm.messages.last?.toolSteps.count == 1 })
        let waiting = try #require(try before.context.fetch(FetchDescriptor<AgentRunRecord>()).first)
        #expect(waiting.status == .awaitingApproval && waiting.node == .approve)
        #expect(waiting.state.rounds == [AgentSavedRound(text: written, calls: [call])], "the round holds the text as the model wrote it")
        #expect(waiting.state.sideEffects == ["c1": .external])
        let threadID = try #require(before.vm.thread?.id)
        let replyID = try #require(before.vm.messages.last?.id)
        // The app is killed: nothing more is saved, and the new process writes no reply yet.
        alive.value = false
        LiveReplies.shared.end(replyID)

        let center = ToolApprovalCenter()
        let after = try await launch(replies: [answer], url: url, thread: threadID, runs: runs, approver: center)
        #expect(await waitUntil { center.pending?.request.call.id == "c1" }, "the card is back")
        let reply = try #require(after.vm.messages.last)
        #expect(reply.id == replyID && reply.toolSteps.map(\.id) == ["c1"], "on the step it waited on")
        #expect(after.vm.phase == .streaming && runs.value == 0)
        return (after.vm, after.context, after.script, center, replyID)
    }

    @Test func allowAfterARelaunchRunsTheToolOnceAndTheModelAnswersFromItsResult() async throws {
        let runs = LocalToolRuns()
        let r = try await relaunchedOnTheWaitingCard(after: "It is sent.", runs: runs)
        r.center.resolveCurrent(.allowOnce)
        #expect(await waitUntil { r.vm.phase == .idle })
        #expect(runs.value == 1, "Allow runs the tool exactly once")
        let reply = try #require(r.vm.messages.last)
        let sent = ToolResult(callID: "c1", name: "send_note", text: "sent", isError: false)
        #expect(reply.toolSteps == [ToolStep(call: call, result: sent, sourceID: ToolSourceCatalog.device.id, approval: .allowOnce)])
        #expect(reply.content == "Sending. It is sent." && reply.failure == nil)
        let request = try #require(r.script.requests.last)
        #expect(r.script.requests.count == 1, "the first generation is not asked again")
        #expect(request.map(\.role) == [.user, .assistant, .user])
        #expect(request[1].content == written, "the model sees its own call")
        #expect(request[2].content.hasPrefix("<tool_response>") && request[2].content.contains("sent"))
        #expect(try r.context.fetch(FetchDescriptor<AgentRunRecord>()).isEmpty, "a run that ends is deleted")
    }

    @Test func denyAfterARelaunchDoesNotRunTheToolAndTheModelGoesOnFromTheRefusal() async throws {
        let runs = LocalToolRuns()
        let r = try await relaunchedOnTheWaitingCard(after: "Understood.", runs: runs)
        r.center.resolveCurrent(.deny)
        #expect(await waitUntil { r.vm.phase == .idle })
        #expect(runs.value == 0, "Deny never runs the tool")
        let reply = try #require(r.vm.messages.last)
        let refused = ToolResult(callID: "c1", name: "send_note", text: ToolResult.deniedText, isError: true)
        #expect(reply.toolSteps == [ToolStep(call: call, result: refused, sourceID: ToolSourceCatalog.device.id, approval: .deny)])
        #expect(reply.content == "Sending. Understood." && reply.failure == nil)
        let request = try #require(r.script.requests.last)
        #expect(request[1].content == written)
        #expect(request[2].content.contains(ToolResult.deniedText), "the model reads that the call was not allowed")
        #expect(try r.context.fetch(FetchDescriptor<AgentRunRecord>()).isEmpty)
    }
}
