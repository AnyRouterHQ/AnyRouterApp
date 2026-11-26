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

struct ToolRowLogicTests {
    @Test func runningTitlesNameTheKindOfWork() {
        #expect(ToolRowLogic.title(for: step("firecrawl_search")) == "Searching the web · firecrawl_search")
        #expect(ToolRowLogic.title(for: step("firecrawl_scrape")) == "Reading a page · firecrawl_scrape")
        #expect(ToolRowLogic.title(for: step("fetch_url")) == "Reading a page · fetch_url")
        #expect(ToolRowLogic.title(for: step("site_crawl")) == "Reading a page · site_crawl")
        #expect(ToolRowLogic.title(for: step("list_models")) == "Using a tool · list_models")
    }

    @Test func doneAndFailedTitlesUsePastTense() {
        #expect(ToolRowLogic.title(for: step("web_search", result: done("web_search"))) == "Searched the web · web_search")
        #expect(ToolRowLogic.title(for: step("scrape", result: done("scrape"))) == "Read a page · scrape")
        #expect(ToolRowLogic.title(for: step("x", result: done("x"))) == "Used a tool · x")
        #expect(ToolRowLogic.title(for: step("web_search", result: done("web_search", isError: true))) == "Search failed · web_search")
        #expect(ToolRowLogic.title(for: step("scrape", result: done("scrape", isError: true))) == "Read failed · scrape")
        #expect(ToolRowLogic.title(for: step("x", result: done("x", isError: true))) == "Tool failed · x")
    }

    @Test func cancelledIsNotShownAsFailed() {
        let cancelled = step("web_search", result: done("web_search", isError: true, text: ToolRowLogic.cancelledText))
        #expect(ToolRowLogic.status(of: cancelled) == .cancelled)
        #expect(ToolRowLogic.title(for: cancelled) == "Search cancelled · web_search")
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

    @Test func toolsSettingDefaultsOnAndPersists() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.toolsEnabled)
        settings.toolsEnabled = false
        #expect(!AppSettings(defaults: defaults).toolsEnabled)
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
        off.settings.toolsEnabled = false
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

    @Test func toolsSwitchFollowsSettingsAndCapability() async throws {
        let r = try await rig(ScriptedEngine())
        #expect(r.vm.supportsTools)
        #expect(r.vm.toolsEnabled)
        r.vm.setToolsEnabled(false)
        #expect(!r.settings.toolsEnabled)
        #expect(!r.vm.toolsEnabled)
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
