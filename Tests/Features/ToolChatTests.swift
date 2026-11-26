import Foundation
import SwiftData
import Testing
@testable import AnyRouter

private func step(_ name: String, result: ToolResult? = nil) -> ToolStep {
    ToolStep(call: ToolCall(id: "c1", name: name, argumentsJSON: "{}"), result: result)
}

private func done(_ name: String, isError: Bool = false, text: String = "ok") -> ToolResult {
    ToolResult(callID: "c1", name: name, text: text, isError: isError)
}

private func args(_ name: String, _ json: String, result: ToolResult? = nil) -> ToolStep {
    ToolStep(call: ToolCall(id: "c1", name: name, argumentsJSON: json), result: result)
}

struct ToolRowLogicTests {
    @Test func titlesNameWhatTheToolDid() {
        let search = #"{"query":"swift 7 release"}"#
        #expect(ToolRowLogic.title(for: args("web_search", search)) == "Searching the web for “swift 7 release”")
        #expect(ToolRowLogic.title(for: args("web_search", search, result: done("web_search"))) == "Searched the web for “swift 7 release”")
        #expect(ToolRowLogic.title(for: args("fetch_url", #"{"url":"https://example.com/docs/a?x=1"}"#, result: done("fetch_url"))) == "Read example.com/docs/a")
        #expect(ToolRowLogic.title(for: args("fetch_url", #"{"url":"https://example.com/"}"#)) == "Reading example.com")
        #expect(ToolRowLogic.title(for: args("calculator", #"{"expression":"2 + 2"}"#, result: done("calculator"))) == "Calculated 2 + 2")
        #expect(ToolRowLogic.title(for: args("current_date_time", "{}", result: done("current_date_time"))) == "Checked the date and time")
        #expect(ToolRowLogic.title(for: args("read_attachment", #"{"name":"notes.txt"}"#, result: done("read_attachment"))) == "Read notes.txt")
    }

    @Test func otherSearchToolsAndUnknownToolsGetGenericTitles() {
        #expect(ToolRowLogic.title(for: step("firecrawl_search")) == "Searching the web")
        #expect(ToolRowLogic.title(for: step("firecrawl_search", result: done("firecrawl_search"))) == "Searched the web")
        #expect(ToolRowLogic.title(for: step("list_models")) == "Using list_models")
        #expect(ToolRowLogic.title(for: step("list_models", result: done("list_models"))) == "Used list_models")
    }

    @Test func missingOrBadArgumentsFallBackToShortTitles() {
        #expect(ToolRowLogic.title(for: args("web_search", "not json")) == "Searching the web")
        #expect(ToolRowLogic.title(for: args("fetch_url", #"{"url":"nope"}"#)) == "Reading a page")
        #expect(ToolRowLogic.title(for: args("read_attachment", "{}")) == "Reading the attachments")
    }

    @Test func longQueriesAreTruncatedOnOneLine() {
        let long = String(repeating: "word ", count: 30)
        let title = ToolRowLogic.title(for: args("web_search", #"{"query":"\#(long)"}"#, result: done("web_search")))
        #expect(title.hasPrefix("Searched the web for “word word"))
        #expect(title.hasSuffix("…”"))
        #expect(title.count < 100)
        let multiline = ToolRowLogic.title(for: args("calculator", #"{"expression":"1+\n2"}"#))
        #expect(!multiline.contains("\n"))
    }

    @Test func failedAndCancelledStepsSaySo() {
        let failed = args("web_search", #"{"query":"x"}"#, result: done("web_search", isError: true))
        #expect(ToolRowLogic.title(for: failed) == "Searched the web for “x” failed")
        #expect(ToolRowLogic.title(for: step("list_models", result: done("list_models", isError: true))) == "Used list_models failed")
        let cancelled = step("web_search", result: done("web_search", isError: true, text: ToolRowLogic.cancelledText))
        #expect(ToolRowLogic.status(of: cancelled) == .cancelled)
        #expect(ToolRowLogic.title(for: cancelled) == "Searched the web cancelled")
    }

    @Test func prettyJSONIndentsAndKeepsOtherTextAsIs() {
        #expect(ToolRowLogic.prettyJSON(#"{"b":1,"a":"x/y"}"#) == "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}")
        #expect(ToolRowLogic.prettyJSON("not json") == "not json")
        #expect(ToolRowLogic.prettyJSON("") == "")
    }

    @Test func clippedCutsLongResultsOnly() {
        #expect(ToolRowLogic.clipped("short") == "short")
        let long = String(repeating: "a", count: 2_500)
        let cut = ToolRowLogic.clipped(long)
        #expect(cut.hasPrefix(String(repeating: "a", count: 2_000)))
        #expect(cut.count < long.count)
        #expect(cut.hasSuffix("characters.]"))
    }
}

@MainActor
struct ToolTraceTests {
    @Test func messageRecordKeepsToolStepsThroughJSON() {
        let record = MessageRecord(role: .assistant, content: "")
        #expect(record.toolSteps.isEmpty)
        #expect(record.toolTraceData == nil)
        let steps = [step("a"), step("b", result: done("b"))]
        record.toolSteps = steps
        #expect(record.toolSteps == steps)
        record.toolSteps = []
        #expect(record.toolTraceData == nil)
    }

    @Test func toolStepsDoNotReachTheModelHistory() {
        let record = MessageRecord(role: .assistant, content: "hi")
        record.toolSteps = [step("a")]
        #expect(record.chatMessage.content == "hi")
    }

    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
        let settings: AppSettings
    }

    private func rig(_ engine: ScriptedEngine, model: ModelDescriptor = testModelWithTools(),
                     host: (any ToolHost)? = StubToolHost()) async throws -> Rig {
        var engine = engine
        engine.models = [model]
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let settings = AppSettings(defaults: testDefaults())
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: settings,
                               models: models, toolHost: { host })
        return Rig(vm: vm, engine: engine, settings: settings)
    }

    private let call = ToolCall(id: "c1", name: "web_search", argumentsJSON: #"{"q":"x"}"#)

    @Test func stepsAreStoredAndFilledAndKeptWithoutText() async throws {
        let result = ToolResult(callID: "c1", name: "web_search", text: "found", isError: false)
        let r = try await rig(ScriptedEngine(deltas: [.toolCall(call), .toolResult(result)]))
        r.vm.input = "Hi"
        await r.vm.send()?.value
        let reply = try #require(r.vm.messages.last)
        #expect(reply.role == .assistant)
        #expect(reply.content.isEmpty)
        #expect(reply.toolSteps == [ToolStep(call: call, result: result)])
    }

    @Test func resultForUnknownCallIsIgnored() async throws {
        let stray = ToolResult(callID: "other", name: "x", text: "", isError: false)
        let r = try await rig(ScriptedEngine(deltas: [.toolCall(call), .toolResult(stray)]))
        r.vm.input = "Hi"
        await r.vm.send()?.value
        #expect(r.vm.messages.last?.toolSteps.first?.call.id == "c1")
    }

    @Test func hostIsPassedOnlyWhenEnabledAndModelHasTools() async throws {
        let on = try await rig(ScriptedEngine(chunks: ["a"]))
        on.vm.input = "Hi"
        await on.vm.send()?.value
        #expect(on.engine.toolsSeen.seen == [["search"]])

        let off = try await rig(ScriptedEngine(chunks: ["a"]))
        off.vm.setToolsEnabled(false)
        off.vm.input = "Hi"
        await off.vm.send()?.value
        #expect(off.engine.toolsSeen.seen == [nil])

        let plain = try await rig(ScriptedEngine(chunks: ["a"]), model: testModel())
        plain.vm.input = "Hi"
        await plain.vm.send()?.value
        #expect(plain.engine.toolsSeen.seen == [nil])
        #expect(!plain.vm.supportsTools)

        let noTools = try await rig(ScriptedEngine(chunks: ["a"]), host: StubToolHost(specs: []))
        noTools.vm.input = "Hi"
        await noTools.vm.send()?.value
        #expect(noTools.engine.toolsSeen.seen == [nil])

        let missing = try await rig(ScriptedEngine(chunks: ["a"]), host: nil)
        missing.vm.input = "Hi"
        await missing.vm.send()?.value
        #expect(missing.engine.toolsSeen.seen == [nil])
    }

    @Test func toolsAreOnByDefaultAndFollowCapability() async throws {
        let r = try await rig(ScriptedEngine())
        #expect(r.vm.supportsTools)
        #expect(r.vm.toolsEnabled)
        r.vm.setToolsEnabled(false)
        #expect(!r.vm.toolsEnabled)
        let plain = try await rig(ScriptedEngine(), model: testModel())
        #expect(!plain.vm.supportsTools)
    }

    @Test func offChoiceIsKeptByTheThreadAndOtherThreadsAreUnaffected() async throws {
        let engine = ScriptedEngine(models: [testModelWithTools()], chunks: ["a"])
        let container = try ModelContainer.anyRouter(inMemory: true)
        let context = ModelContext(container)
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        func makeVM(_ thread: ThreadRecord?) -> ChatViewModel {
            ChatViewModel(thread: thread, context: context, registry: registry,
                          settings: AppSettings(defaults: testDefaults()), models: models,
                          toolHost: { StubToolHost() })
        }

        // Off before the first send: the new thread keeps the choice.
        let first = makeVM(nil)
        first.setToolsEnabled(false)
        first.input = "Hi"
        await first.send()?.value
        let firstThread = try #require(first.thread)
        #expect(firstThread.toolsDisabled)

        // A thread nobody touched stays on.
        let second = makeVM(nil)
        #expect(second.toolsEnabled)
        second.input = "Hi"
        await second.send()?.value
        let secondThread = try #require(second.thread)
        #expect(!secondThread.toolsDisabled)

        // Reopening restores each choice; switching back on is saved.
        let reopened = makeVM(firstThread)
        #expect(!reopened.toolsEnabled)
        #expect(makeVM(secondThread).toolsEnabled)
        reopened.setToolsEnabled(true)
        #expect(!firstThread.toolsDisabled)
    }

    @Test func threadRecordDefaultsToToolsOn() {
        #expect(!ThreadRecord().toolsDisabled)
    }

    @Test func stopMarksRunningStepsCancelled() async throws {
        let r = try await rig(ScriptedEngine(hangs: true, deltas: [.toolCall(call)]))
        r.vm.input = "Hi"
        let task = try #require(r.vm.send())
        #expect(await waitUntil { r.vm.messages.last?.toolSteps.count == 1 })
        r.vm.stop()
        await task.value
        let step = try #require(r.vm.messages.last?.toolSteps.first)
        #expect(step.result == ToolResult(callID: "c1", name: "web_search", text: "Cancelled", isError: true))
        #expect(ToolRowLogic.status(of: step) == .cancelled)
    }
}

@MainActor
struct ToolApprovalTests {
    private func request(_ name: String) -> ToolApprovalRequest {
        ToolApprovalRequest(
            serverName: "S",
            spec: ToolSpec(name: name, title: nil, description: "", inputSchemaJSON: "{}", isReadOnly: false),
            call: ToolCall(id: name, name: name, argumentsJSON: "{}"))
    }

    @Test func choiceResumesTheCaller() async {
        let center = ToolApprovalCenter()
        let asked = Task { await center.decide(request("a")) }
        #expect(await waitUntil { center.pending != nil })
        #expect(center.pending?.request.spec.name == "a")
        center.resolveCurrent(.alwaysAllow)
        #expect(await asked.value == .alwaysAllow)
        #expect(center.pending == nil)
    }

    @Test func cancelledCallerIsDeniedAndDropped() async {
        let center = ToolApprovalCenter()
        let asked = Task { await center.decide(request("a")) }
        #expect(await waitUntil { center.pending != nil })
        asked.cancel()
        #expect(await asked.value == .deny)
        #expect(await waitUntil { center.pending == nil })
        center.resolveCurrent(.allowOnce)  // nothing pending: harmless
    }

    @Test func callerCancelledBeforeItArrivesIsNeverShown() async {
        let center = ToolApprovalCenter()
        let asked = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await center.decide(request("a"))
        }
        #expect(await asked.value == .deny)
        #expect(center.pending == nil)
    }

    @Test func twoRequestsAreServedOneAtATime() async {
        let center = ToolApprovalCenter()
        let first = Task { await center.decide(request("a")) }
        #expect(await waitUntil { center.pending != nil })
        let second = Task { await center.decide(request("b")) }
        // Give the second request time to queue behind the first.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(center.pending?.request.spec.name == "a")
        center.resolveCurrent(.allowOnce)
        #expect(await first.value == .allowOnce)
        #expect(await waitUntil { center.pending?.request.spec.name == "b" })
        center.resolveCurrent(.deny)
        #expect(await second.value == .deny)
        #expect(center.pending == nil)
    }
}

struct ToolApprovalPromptTests {
    private func request(args: String, title: String? = "Send a note") -> ToolApprovalRequest {
        ToolApprovalRequest(
            serverName: "Example",
            spec: ToolSpec(name: "send_note", title: title, description: "", inputSchemaJSON: "{}", isReadOnly: false),
            call: ToolCall(id: "1", name: "send_note", argumentsJSON: args))
    }

    @Test func titleNamesTheToolAndFallsBackToItsName() {
        #expect(ToolApprovalPrompt.title(for: request(args: "{}")) == "Allow Send a note?")
        #expect(ToolApprovalPrompt.title(for: request(args: "{}", title: nil)) == "Allow send_note?")
    }

    @Test func messageHasServerAndCompactArguments() {
        let message = ToolApprovalPrompt.message(for: request(args: "{ \"to\": \"team\",\n  \"text\": \"a/b\" }"))
        #expect(message == "Example\n{\"text\":\"a/b\",\"to\":\"team\"}")
    }

    @Test func longArgumentsAreCut() {
        let long = "{\"text\":\"" + String(repeating: "a", count: 500) + "\"}"
        let text = ToolApprovalPrompt.compactJSON(long)
        #expect(text.count == ToolApprovalPrompt.maxArgumentCharacters + 1)
        #expect(text.hasSuffix("…"))
        #expect(ToolApprovalPrompt.compactJSON("not json") == "not json")
    }
}

struct ToolApprovalQueueTests {
    private func entry() -> ToolApprovalQueue.Entry {
        .init(id: UUID(), request: ToolApprovalRequest(
            serverName: "S",
            spec: ToolSpec(name: "t", title: nil, description: "", inputSchemaJSON: "{}", isReadOnly: false),
            call: ToolCall(id: "1", name: "t", argumentsJSON: "{}")))
    }

    @Test func keepsArrivalOrderAndRemovesById() {
        var queue = ToolApprovalQueue()
        let a = entry(), b = entry()
        let firstQueued = queue.enqueue(a)
        let secondQueued = queue.enqueue(b)
        #expect(firstQueued && secondQueued)
        #expect(queue.current == a)
        let removed = queue.remove(id: a.id)
        #expect(removed)
        #expect(queue.current == b)
        let removedAgain = queue.remove(id: a.id)
        #expect(!removedAgain)
    }

    @Test func earlyCancelRefusesTheRequestOnArrival() {
        var queue = ToolApprovalQueue()
        let a = entry()
        let wasQueued = queue.remove(id: a.id, markIfMissing: true)
        let accepted = queue.enqueue(a)
        #expect(!wasQueued)
        #expect(!accepted)
        #expect(queue.current == nil)
    }
}
