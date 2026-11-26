import Foundation
import Testing
@testable import AnyRouter

struct TopPicksTests {
    private let config = TopPicksConfig(
        curated: ["anyrouter/auto", "anyrouter/free"],
        fallback: ["anthropic/claude-sonnet", "openai/gpt-5"], usageCount: 3)

    private func world(signedIn: Bool = true) -> [ModelDescriptor] {
        [
            cloudModel("anyrouter/auto", usable: signedIn),
            cloudModel("anyrouter/free", usable: signedIn),
            cloudModel("anyrouter/coding", usable: signedIn),
            cloudModel("anthropic/claude-sonnet", usable: signedIn),
            cloudModel("openai/gpt-5", usable: signedIn),
            cloudModel("google/gemini", usable: signedIn),
            cloudModel("vendor/locked", availability: .needsKey, usable: signedIn),
            cloudModel("vendor/small", usable: signedIn),
            cloudModel("vendor/big", usable: signedIn),
        ]
    }

    private func ids(_ models: [ModelDescriptor]) -> [String] { models.map(\.wireID) }

    @Test func routersLeadThenTheMostUsedUsableModels() {
        let rank = ["vendor/locked": 0, "google/gemini": 1, "vendor/big": 2, "anyrouter/coding": 3, "openai/gpt-5": 4, "vendor/small": 5]
        let picks = TopPicks.compose(config: config, models: world(), usageRank: rank)
        // The locked model is skipped, the coding router is not a "most used" pick, three models are added.
        #expect(ids(picks) == ["anyrouter/auto", "anyrouter/free", "google/gemini", "vendor/big", "openai/gpt-5"])
    }

    @Test func offlineUsesTheBundledFallbackList() {
        let picks = TopPicks.compose(config: config, models: world(), usageRank: [:])
        #expect(ids(picks) == ["anyrouter/auto", "anyrouter/free", "anthropic/claude-sonnet", "openai/gpt-5"])
    }

    @Test func offlineFallbackSkipsModelsTheUserCannotUse() {
        var models = world()
        models.removeAll { $0.wireID == "openai/gpt-5" }
        models.append(cloudModel("openai/gpt-5", availability: .needsKey))
        let picks = TopPicks.compose(config: config, models: models, usageRank: [:])
        #expect(ids(picks) == ["anyrouter/auto", "anyrouter/free", "anthropic/claude-sonnet"])
    }

    @Test func signedOutHasNothingToPick() {
        #expect(TopPicks.compose(config: config, models: world(signedIn: false), usageRank: ["google/gemini": 0]).isEmpty)
    }

    @Test func aMissingCuratedModelIsSimplySkipped() {
        var models = world()
        models.removeAll { $0.wireID == "anyrouter/free" }
        let picks = TopPicks.compose(config: config, models: models, usageRank: [:])
        #expect(ids(picks).first == "anyrouter/auto")
        #expect(!ids(picks).contains("anyrouter/free"))
    }

    @Test func nothingIsListedTwice() {
        let rank = ["anyrouter/auto": 0, "google/gemini": 1]
        let picks = TopPicks.compose(
            config: TopPicksConfig(curated: ["anyrouter/auto", "google/gemini"], fallback: [], usageCount: 3),
            models: world(), usageRank: rank)
        #expect(Set(ids(picks)).count == picks.count)
        #expect(ids(picks) == ["anyrouter/auto", "google/gemini"])
    }

    @Test func theBundledFileDecodesAndMatchesTheStandardConfig() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Features/ModelPicker/top-picks.json")
        let decoded = try JSONDecoder().decode(TopPicksConfig.self, from: Data(contentsOf: url))
        #expect(decoded == TopPicksConfig.standard)
        #expect(decoded.curated.first == "anyrouter/auto")
    }
}

@MainActor
struct UsageOrderTests {
    private final class FakeSource: UsageOrderSource, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var ids: [String]
        var fails = false
        init(ids: [String]) { self.ids = ids }
        var callCount: Int { lock.withLock { calls } }
        func fetchUsageOrder() async throws -> [String] {
            lock.withLock { calls += 1 }
            if fails { throw TestFailure(message: "offline") }
            return ids
        }
    }

    private func store(_ source: FakeSource?, defaults: UserDefaults) -> ModelStore {
        ModelStore(registry: EngineRegistry(), defaults: defaults, usage: source)
    }

    @Test func theOrderIsFetchedAndRanked() async {
        let source = FakeSource(ids: ["b", "a", "c"])
        let s = store(source, defaults: testDefaults())
        await s.refreshUsageOrder()
        #expect(s.usageRank == ["b": 0, "a": 1, "c": 2])
    }

    @Test func itIsFetchedAtMostEverySixHours() async {
        let source = FakeSource(ids: ["a"])
        let defaults = testDefaults()
        let s = store(source, defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)
        await s.refreshUsageOrder(now: start)
        await s.refreshUsageOrder(now: start.addingTimeInterval(5 * 3600))
        #expect(source.callCount == 1)
        source.ids = ["b"]
        await s.refreshUsageOrder(now: start.addingTimeInterval(6 * 3600 + 1))
        #expect(source.callCount == 2)
        #expect(s.usageOrder == ["b"])
    }

    @Test func aNewStoreStartsFromTheCache() async {
        let defaults = testDefaults()
        await store(FakeSource(ids: ["x", "y"]), defaults: defaults).refreshUsageOrder()
        let second = store(nil, defaults: defaults)
        #expect(second.usageOrder == ["x", "y"])
    }

    @Test func offlineKeepsTheCachedOrderAndFirstLaunchHasNone() async {
        let defaults = testDefaults()
        let first = FakeSource(ids: ["x"])
        await store(first, defaults: defaults).refreshUsageOrder(now: Date(timeIntervalSince1970: 0))
        let offline = FakeSource(ids: [])
        offline.fails = true
        let s = store(offline, defaults: defaults)
        await s.refreshUsageOrder(now: Date(timeIntervalSince1970: 7 * 3600)) // stale, fetch fails
        #expect(s.usageOrder == ["x"])
        let fresh = store(offline, defaults: testDefaults())
        await fresh.refreshUsageOrder()
        #expect(fresh.usageOrder.isEmpty)
        #expect(fresh.usageRank.isEmpty)
    }

    @Test func refreshingModelsAlsoRefreshesTheOrder() async {
        let source = FakeSource(ids: ["a"])
        let s = store(source, defaults: testDefaults())
        await s.refresh()
        #expect(s.usageOrder == ["a"])
    }
}
