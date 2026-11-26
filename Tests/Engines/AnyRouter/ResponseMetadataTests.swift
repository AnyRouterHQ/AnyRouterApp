import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// The last SSE chunk of a request through anyrouter/auto, as the API sends it (fixture also used by the coverage lane).
enum MetadataFixture {
    static let sse = """
        data: {"id":"gen-1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hel"},"finish_reason":null}]}

        data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":null}]}

        data: {"id":"gen-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":34,"total_tokens":46},"anyrouter_metadata":{"requestId":"req_abc123","model":"nvidia/nemotron-3.5-bolt-e4b","upstream":{"provider":"NVIDIA","backend":"numes","name":"nemotron-3.5-bolt-e4b","latencyMs":812},"credentialSource":"pool","usage":{"inputTokens":12,"outputTokens":34,"cachedTokens":4,"totalTokens":46},"cost":{"amount":0.0004,"currency":"USD"},"finishReason":"stop","providerChain":["numes"]}}

        data: [DONE]


        """

    /// Same, but the server sends the token counts only inside the metadata.
    static let metadataOnlyUsage = """
        data: {"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"anyrouter_metadata":{"requestId":"r2","model":"openai/gpt-5","usage":{"inputTokens":5,"outputTokens":6,"totalTokens":11},"cost":{"amount":"0.01","currency":"USD"}}}

        data: [DONE]


        """

    static func decode(_ text: String) throws -> [ChatDelta] {
        var parser = SSEParser()
        var decoder = ChatChunkDecoder()
        var out: [ChatDelta] = []
        for payload in parser.feed(Data(text.utf8)) + parser.finish() { out += try decoder.decode(payload) }
        return out
    }
}

struct ResponseMetadataTests {
    private func metadata(_ deltas: [ChatDelta]) -> ResponseMetadata? {
        deltas.compactMap { if case .metadata(let m) = $0 { m } else { nil } }.first
    }

    @Test func realLastChunkGivesServedModelCostAndTokens() throws {
        let deltas = try MetadataFixture.decode(MetadataFixture.sse)
        let m = try #require(metadata(deltas))
        #expect(m.requestID == "req_abc123")
        #expect(m.servedModelID == "nvidia/nemotron-3.5-bolt-e4b")
        #expect(m.provider == "NVIDIA")
        #expect(m.costUSD == Decimal(string: "0.0004"))
        #expect(m.promptTokens == 12)
        #expect(m.completionTokens == 34)
        #expect(m.cachedTokens == 4)
        #expect(m.upstreamLatencyMs == 812)
    }

    @Test func tokenCountsAreReportedOnceEvenWhenBothFieldsAreThere() throws {
        let deltas = try MetadataFixture.decode(MetadataFixture.sse)
        let usages = deltas.filter { if case .usage = $0 { true } else { false } }
        #expect(usages == [.usage(prompt: 12, completion: 34)])
    }

    @Test func metadataAloneStillGivesUsageAndAStringCost() throws {
        let deltas = try MetadataFixture.decode(MetadataFixture.metadataOnlyUsage)
        #expect(deltas.contains(.usage(prompt: 5, completion: 6)))
        #expect(metadata(deltas)?.costUSD == Decimal(string: "0.01"))
    }

    @Test func aStreamWithoutMetadataStillWorks() throws {
        let deltas = try MetadataFixture.decode("""
            data: {"choices":[{"index":0,"delta":{"content":"x"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2}}

            data: [DONE]


            """)
        #expect(metadata(deltas) == nil)
        #expect(deltas.contains(.usage(prompt: 1, completion: 2)))
    }

    @Test func aCostInAnotherCurrencyIsNotShownAsDollars() {
        let raw: [String: Any] = ["requestId": "r", "cost": ["amount": 5, "currency": "EUR"]]
        let m = ChatChunkDecoder.metadata(from: raw)
        #expect(m?.requestID == "r")
        #expect(m?.costUSD == nil)
    }

    @Test func tokensPerSecondCountsFromTheFirstToken() {
        var m = ResponseMetadata(completionTokens: 30)
        m.ttftMs = 500
        m.totalMs = 2500
        #expect(m.tokensPerSecond == 15)
        m.totalMs = 500
        #expect(m.tokensPerSecond == nil)
        m.totalMs = 520 // too short to mean anything
        #expect(m.tokensPerSecond == nil)
        #expect(ResponseMetadata(completionTokens: 0, ttftMs: 1, totalMs: 1000).tokensPerSecond == nil)
    }

    @Test func tworoundsOfAToolReplyAddUp() {
        let first = ResponseMetadata(
            requestID: "a", servedModelID: "x/one", provider: "P1", costUSD: Decimal(string: "0.001"),
            promptTokens: 10, completionTokens: 5, upstreamLatencyMs: 100)
        let second = ResponseMetadata(
            requestID: "b", servedModelID: "x/one", provider: "P2", costUSD: Decimal(string: "0.002"),
            promptTokens: 20, completionTokens: 7, cachedTokens: 3, upstreamLatencyMs: 50)
        let sum = ResponseMetadata.combining(first, second)
        #expect(sum?.costUSD == Decimal(string: "0.003"))
        #expect(sum?.promptTokens == 30)
        #expect(sum?.completionTokens == 12)
        #expect(sum?.cachedTokens == 3)
        #expect(sum?.upstreamLatencyMs == 150)
        #expect(sum?.requestID == "b")
        #expect(sum?.provider == "P2")
        #expect(ResponseMetadata.combining(nil, second) == second)
        #expect(ResponseMetadata.combining(first, nil) == first)
    }
}

struct ResponseFormatTests {
    @Test func timesAreShortAndReadable() {
        #expect(ResponseFormat.seconds(600) == "0.6s")
        #expect(ResponseFormat.seconds(2100) == "2.1s")
        #expect(ResponseFormat.seconds(12_400) == "12s")
        #expect(ResponseFormat.seconds(40) == "<0.1s")
        #expect(ResponseFormat.speed(38.4) == "38 tok/s")
    }

    @Test func summaryListsWhatIsKnownInOrder() {
        var m = ResponseMetadata(costUSD: Decimal(string: "0.0004"), promptTokens: 12, completionTokens: 34)
        m.ttftMs = 600
        m.totalMs = 2100
        #expect(ResponseFormat.summary(m) == ["$0.0004", "0.6s first token", "2.1s", "23 tok/s", "12 in / 34 out"])
        #expect(ResponseFormat.summary(ResponseMetadata(costUSD: 0)) == ["Free"])
        #expect(ResponseFormat.summary(ResponseMetadata()).isEmpty)
    }

    @Test func autoShowsWhichModelItRoutedTo() {
        let routed = ResponseMetadata(servedModelID: "nvidia/nemotron-3.5-bolt-e4b", servedModelName: "Nemotron 3.5 Bolt E4B")
        #expect(ResponseFormat.title(requestedName: "AnyRouter", requestedID: "anyrouter/anyrouter/auto", metadata: routed)
            == "AnyRouter → Nemotron 3.5 Bolt E4B")
        // A normal model keeps its own name.
        let same = ResponseMetadata(servedModelID: "openai/gpt-5", servedModelName: "GPT-5")
        #expect(ResponseFormat.title(requestedName: "GPT-5", requestedID: "anyrouter/openai/gpt-5", metadata: same) == "GPT-5")
        // Old replies have a name but no metadata.
        #expect(ResponseFormat.title(requestedName: "GPT-5", requestedID: nil, metadata: nil) == "GPT-5")
        #expect(ResponseFormat.title(requestedName: nil, requestedID: nil, metadata: nil) == nil)
    }

    @Test func prettyNameReadsAnIdWhenTheListDoesNotKnowIt() {
        #expect(ResponseFormat.prettyName("nvidia/nemotron-3.5-bolt-e4b") == "Nemotron 3.5 Bolt E4B")
        #expect(ResponseFormat.prettyName("z-ai/glm-5.3-flash") == "Glm 5.3 Flash")
    }
}

/// The timings are measured by the chat with an injected clock, and saved with the reply.
@MainActor
struct ResponseTimingTests {
    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval]
        init(_ values: [TimeInterval]) { self.values = values }
        func next() -> TimeInterval { lock.withLock { values.count > 1 ? values.removeFirst() : (values.first ?? 0) } }
    }

    private func rig(_ model: ModelDescriptor, engine: ScriptedEngine, clock: FakeClock) async throws -> (ChatViewModel, ModelContext) {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models, now: clock.next)
        vm.choose(model)
        return (vm, context)
    }

    @Test func firstTokenAndTotalTimeComeFromTheClock() async throws {
        // start, first text, end
        let clock = FakeClock([100, 100.6, 102.1])
        var engine = ScriptedEngine(source: .anyrouter, models: [cloudModel("anyrouter/auto", name: "AnyRouter Auto")])
        engine.chunks = ["Hello"]
        engine.deltas = [
            .usage(prompt: 12, completion: 30),
            .metadata(ResponseMetadata(
                requestID: "req_1", servedModelID: "nvidia/nemotron-3.5-bolt-e4b", provider: "NVIDIA",
                costUSD: Decimal(string: "0.0004"))),
        ]
        let (vm, _) = try await rig(cloudModel("anyrouter/auto", name: "AnyRouter Auto"), engine: engine, clock: clock)
        vm.input = "hi"
        await vm.send()?.value

        let m = try #require(vm.messages.last?.metadata)
        #expect(m.ttftMs == 600)
        #expect(m.totalMs == 2100)
        #expect(m.tokensPerSecond == 20) // 30 tokens over the 1.5 s after the first token
        #expect(m.servedModelID == "nvidia/nemotron-3.5-bolt-e4b")
        #expect(m.servedModelName == "Nemotron 3.5 Bolt E4B") // not in the list, so read from the id
        #expect(m.provider == "NVIDIA")
        #expect(m.costUSD == Decimal(string: "0.0004"))
        #expect(m.promptTokens == 12)
        #expect(m.completionTokens == 30)
        #expect(m.requestID == "req_1")
    }

    @Test func localAndAppleRepliesAreOnDeviceAndFree() async throws {
        let clock = FakeClock([10, 10.2, 11])
        var engine = ScriptedEngine(source: .apple, models: [testModel(id: "apple/foundation", source: .apple)])
        engine.chunks = ["ok"]
        let (vm, _) = try await rig(testModel(id: "apple/foundation", source: .apple), engine: engine, clock: clock)
        vm.input = "hi"
        await vm.send()?.value
        let m = try #require(vm.messages.last?.metadata)
        #expect(m.provider == "On device")
        #expect(m.costUSD == 0)
        #expect(m.servedModelID == "apple/foundation")
        #expect(m.ttftMs == 200)
        #expect(m.totalMs == 1000)
    }

    @Test func theMetadataIsSavedWithTheReplyAndComesBack() async throws {
        let clock = FakeClock([0, 0.3, 1])
        var engine = ScriptedEngine(source: .apple, models: [testModel(id: "apple/foundation", source: .apple)])
        engine.chunks = ["ok"]
        let (vm, context) = try await rig(testModel(id: "apple/foundation", source: .apple), engine: engine, clock: clock)
        vm.input = "hi"
        await vm.send()?.value
        try context.save()
        let id = try #require(vm.messages.last?.id)
        let fetched = try context.fetch(FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.first?.metadata?.totalMs == 1000)
        #expect(fetched.first?.metadata?.provider == "On device")
    }

    @Test func aServedModelThatIsInTheListUsesItsListName() {
        let known = cloudModel("openai/gpt-5-mini", name: "GPT-5 mini")
        let m = ChatViewModel.finalMetadata(
            ResponseMetadata(servedModelID: "openai/gpt-5-mini"), tokens: nil,
            model: cloudModel("anyrouter/auto"), ttftMs: nil, totalMs: 10,
            nameOf: { id in id == known.wireID ? known.displayName : nil })
        #expect(m.servedModelName == "GPT-5 mini")
    }

    @Test func aServerWithoutMetadataStillGetsTimingsAndTheRequestedModel() {
        let model = cloudModel("openai/gpt-5", name: "GPT-5")
        let m = ChatViewModel.finalMetadata(nil, tokens: (3, 4), model: model, ttftMs: 200, totalMs: 900, nameOf: { _ in nil })
        #expect(m.servedModelID == "openai/gpt-5")
        #expect(m.servedModelName == "GPT-5")
        #expect(m.promptTokens == 3)
        #expect(m.completionTokens == 4)
        #expect(m.costUSD == nil)
        #expect(m.provider == nil)
    }
}
