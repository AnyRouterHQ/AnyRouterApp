import Foundation
import Testing
@testable import AnyRouter

private func reply(_ body: String, status: Int = 200) -> StubRegistry.Reply {
    StubRegistry.Reply(status: status, body: Data(body.utf8))
}

struct ResponseMetadataGapTests {
    @Test func theSecondRoundOnlyAddsWhatItKnowsAndKeepsEarlierNames() {
        let first = ResponseMetadata(requestID: "r1", servedModelID: "m1", servedModelName: "M", provider: "P", costUSD: 1, promptTokens: 3)
        let second = ResponseMetadata(costUSD: 2, completionTokens: 4)
        let combined = ResponseMetadata.combining(first, second)
        #expect(combined?.requestID == "r1")
        #expect(combined?.servedModelID == "m1")
        #expect(combined?.servedModelName == "M")
        #expect(combined?.provider == "P")
        #expect(combined?.costUSD == 3)
        #expect(combined?.promptTokens == 3)
        #expect(combined?.completionTokens == 4)
    }

    @Test func theSecondRoundNamesWinWhenItHasThem() {
        let combined = ResponseMetadata.combining(ResponseMetadata(requestID: "r1", provider: "A"), ResponseMetadata(requestID: "r2", provider: "B"))
        #expect(combined?.requestID == "r2")
        #expect(combined?.provider == "B")
        #expect(ResponseMetadata.combining(nil, ResponseMetadata(requestID: "x"))?.requestID == "x")
        #expect(ResponseMetadata.combining(ResponseMetadata(requestID: "y"), nil)?.requestID == "y")
    }
}

struct PublicEndpointTests {
    @Test func weeklyUsageListsModelsByRankWithTheirCounts() async throws {
        let seen = Flag()
        let body = ##"{"period":{"key":"this_week"},"models":[{"model_id":"b/y","rank":2,"tokens":900,"requests":7},{"model_id":"a/x","rank":1,"tokens":10893316278,"requests":53975,"cost":4.2}]}"##
        let api = StubbedAPI { request in
            let query = request.url?.query ?? ""
            seen.value = request.url?.path == "/api/v1/analytics/top-models" && query.contains("period=this_week") && query.contains("limit=500")
            return reply(body)
        }
        let usage = try await AnyRouterWeeklyUsage(config: api.config, session: api.session).fetchWeeklyUsage()
        #expect(seen.value)
        #expect(usage == [
            ModelUsage(id: "a/x", rank: 1, tokens: 10_893_316_278, requests: 53_975),
            ModelUsage(id: "b/y", rank: 2, tokens: 900, requests: 7),
        ])
    }

    @Test func weeklyUsageReportsServerErrors() async {
        let api = StubbedAPI { _ in reply("", status: 503) }
        let source = AnyRouterWeeklyUsage(config: api.config, session: api.session)
        await #expect(throws: AnyRouterError.http(status: 503, message: "Request failed (HTTP 503).")) { try await source.fetchWeeklyUsage() }
        _ = AnyRouterWeeklyUsage()
    }

    @Test func routingPreviewListsTheFailoverChainWithPrices() async throws {
        let body = #"{"resolved":[{"id":"openai/gpt","name":"GPT","provider":"OpenAI","context_length":1000,"input_price_per_1m":"1.5","output_price_per_1m":2},{"id":"x/y"}]}"#
        let path = Flag()
        let api = StubbedAPI { request in
            path.value = request.url?.path == "/api/v1/models/anyrouter/auto/routing-preview"
            return reply(body)
        }
        let members = try await AnyRouterRoutingPreview(config: api.config, session: api.session).members(of: "anyrouter/auto")
        #expect(path.value)
        #expect(members.map(\.name) == ["GPT", "x/y"])
        #expect(members.first?.inputPer1M == Decimal(string: "1.5"))
        #expect(members.first?.outputPer1M == 2)
        #expect(members.first?.contextLength == 1000)
        #expect(members.last?.provider == nil)
    }

    @Test func routingPreviewReportsServerErrors() async {
        let api = StubbedAPI { _ in reply(#"{"error":{"message":"no such router"}}"#, status: 404) }
        let preview = AnyRouterRoutingPreview(config: api.config, session: api.session)
        await #expect(throws: AnyRouterError.http(status: 404, message: "no such router")) { try await preview.members(of: "anyrouter/none") }
        _ = AnyRouterRoutingPreview()
    }

    @Test func aStreamWithMetadataStillDeliversItsText() async throws {
        let api = StubbedAPI { _ in
            reply("""
                data: {"choices":[{"delta":{"content":"hi"}}]}

                data: {"choices":[],"anyrouter_metadata":{"requestId":"r1","model":"openai/gpt-5"}}

                data: [DONE]


                """)
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        var texts: [String] = []
        for try await delta in engine.stream(model: testModel(id: "anyrouter/openai/gpt-5", source: .anyrouter), messages: [], params: GenerationParams()) {
            if case .text(let piece) = delta { texts.append(piece) }
        }
        #expect(texts == ["hi"])
    }
}

struct ModelsResponseGapTests {
    @Test func aBareModelEntryDecodesWithoutArchitectureOrCapabilities() throws {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(#"{"data":[{"id":"a/b","category":"text"}]}"#.utf8))
        let models = response.descriptors(usable: true)
        #expect(models.map(\.id) == ["anyrouter/a/b"])
        #expect(models.first?.cloud?.supportsVision == false)
    }

    @Test func pricesDecodeFromNumbersAndStringsAndIgnoreOtherShapes() throws {
        func amount(_ json: String) throws -> Decimal? {
            try JSONDecoder().decode(ModelsResponse.Amount.self, from: Data(json.utf8)).value
        }
        #expect(try amount("2") == 2)
        #expect(try amount(#""1.5""#) == Decimal(string: "1.5"))
        #expect(try amount("true") == nil)
    }
}

@MainActor
struct PickerOrderGapTests {
    private struct DuplicateOrder: WeeklyUsageSource {
        func fetchWeeklyUsage() async throws -> [ModelUsage] {
            [
                ModelUsage(id: "a", rank: 1, tokens: 3, requests: 1),
                ModelUsage(id: "b", rank: 2, tokens: 2, requests: 1),
                ModelUsage(id: "a", rank: 3, tokens: 1, requests: 1),
            ]
        }
    }

    @Test func aModelListedTwiceKeepsItsBestPlaceInTheUsageOrder() async {
        let store = ModelStore(registry: EngineRegistry(), defaults: testDefaults(), usage: DuplicateOrder())
        await store.refreshWeeklyUsage()
        #expect(store.usageRank == ["a": 0, "b": 1])
        #expect(store.weeklyUsage["a"]?.rank == 1)
    }

    @Test func tabsAndSortsHaveIDsAndTitles() {
        #expect(PickerTab.allCases.map(\.id) == ["local", "anyrouter"])
        #expect(PickerTab.allCases.map(\.title) == ["Local", "AnyRouter"])
        #expect(PickerSort.allCases.map(\.id) == ["topUsage", "newest", "cheapest", "free", "name"])
        #expect(PickerSort.allCases.map(\.title) == ["Top this week", "Newest", "Cheapest", "Free", "Name"])
    }

    @Test func presetsSortByNameWithTheOtherModels() {
        func model(_ id: String, _ name: String) -> ModelDescriptor {
            var model = testModel(id: "anyrouter/\(id)", source: .anyrouter)
            model.displayName = name
            return model
        }
        let list = CloudListLogic.arrange(
            models: [model("anyrouter/coding", "Zed"), model("vendor/mid", "Mid"), model("anyrouter/zzz1", "Alpha")],
            query: "", sort: .name, usageRank: [:], showUnusable: true)
        #expect(list.rest.map(\.displayName) == ["Alpha", "Mid", "Zed"], "a preset gets no place at the top")
    }
}
