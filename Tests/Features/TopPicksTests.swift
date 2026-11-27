import Foundation
import Testing
@testable import AnyRouter

struct TopPicksTests {
    private let config = TopPicksConfig(
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

    @Test func theMostUsedUsableModelsPresetsIncluded() {
        let rank = ["vendor/locked": 0, "google/gemini": 1, "vendor/big": 2, "anyrouter/coding": 3, "openai/gpt-5": 4, "vendor/small": 5]
        let picks = TopPicks.compose(config: config, models: world(), usageRank: rank)
        // The locked model is skipped; a preset counts like any other model; three models.
        #expect(ids(picks) == ["google/gemini", "vendor/big", "anyrouter/coding"])
    }

    @Test func offlineUsesTheBundledFallbackList() {
        let picks = TopPicks.compose(config: config, models: world(), usageRank: [:])
        #expect(ids(picks) == ["anthropic/claude-sonnet", "openai/gpt-5"], "no preset is pinned in front")
    }

    @Test func offlineFallbackSkipsModelsTheUserCannotUse() {
        var models = world()
        models.removeAll { $0.wireID == "openai/gpt-5" }
        models.append(cloudModel("openai/gpt-5", availability: .needsKey))
        let picks = TopPicks.compose(config: config, models: models, usageRank: [:])
        #expect(ids(picks) == ["anthropic/claude-sonnet"])
    }

    @Test func signedOutHasNothingToPick() {
        #expect(TopPicks.compose(config: config, models: world(signedIn: false), usageRank: ["google/gemini": 0]).isEmpty)
    }

    @Test func theBundledFileDecodesAndMatchesTheStandardConfig() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Features/ModelPicker/top-picks.json")
        let decoded = try JSONDecoder().decode(TopPicksConfig.self, from: Data(contentsOf: url))
        #expect(decoded == TopPicksConfig.standard)
    }
}

@MainActor
struct WeeklyUsageTests {
    private final class FakeSource: WeeklyUsageSource, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var usage: [ModelUsage]
        var fails = false
        init(ids: [String]) { usage = Self.rows(ids) }
        var callCount: Int { lock.withLock { calls } }
        static func rows(_ ids: [String]) -> [ModelUsage] {
            ids.enumerated().map { ModelUsage(id: $1, rank: $0 + 1, tokens: 1000 * (ids.count - $0), requests: 10) }
        }
        func fetchWeeklyUsage() async throws -> [ModelUsage] {
            lock.withLock { calls += 1 }
            if fails { throw TestFailure(message: "offline") }
            return usage
        }
    }

    private func store(_ source: FakeSource?, defaults: UserDefaults) -> ModelStore {
        ModelStore(registry: EngineRegistry(), defaults: defaults, usage: source)
    }

    @Test func theUsageIsFetchedAndRanked() async {
        let source = FakeSource(ids: ["b", "a", "c"])
        let s = store(source, defaults: testDefaults())
        await s.refreshWeeklyUsage()
        #expect(s.usageRank == ["b": 0, "a": 1, "c": 2])
        #expect(s.weeklyUsage["a"]?.rank == 2)
        #expect(s.weeklyUsage["b"]?.tokens == 3000)
    }

    @Test func itIsFetchedAtMostEverySixHours() async {
        let source = FakeSource(ids: ["a"])
        let defaults = testDefaults()
        let s = store(source, defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)
        await s.refreshWeeklyUsage(now: start)
        await s.refreshWeeklyUsage(now: start.addingTimeInterval(5 * 3600))
        #expect(source.callCount == 1)
        source.usage = FakeSource.rows(["b"])
        await s.refreshWeeklyUsage(now: start.addingTimeInterval(6 * 3600 + 1))
        #expect(source.callCount == 2)
        #expect(s.usageRank == ["b": 0])
        #expect(s.weeklyUsage["a"] == nil)
    }

    @Test func aNewStoreStartsFromTheCache() async {
        let defaults = testDefaults()
        await store(FakeSource(ids: ["x", "y"]), defaults: defaults).refreshWeeklyUsage()
        let second = store(nil, defaults: defaults)
        #expect(second.usageRank == ["x": 0, "y": 1])
        #expect(second.weeklyUsage["y"]?.rank == 2)
    }

    @Test func offlineKeepsTheCachedUsageAndFirstLaunchHasNone() async {
        let defaults = testDefaults()
        let first = FakeSource(ids: ["x"])
        await store(first, defaults: defaults).refreshWeeklyUsage(now: Date(timeIntervalSince1970: 0))
        let offline = FakeSource(ids: [])
        offline.fails = true
        let s = store(offline, defaults: defaults)
        await s.refreshWeeklyUsage(now: Date(timeIntervalSince1970: 7 * 3600)) // stale, fetch fails
        #expect(s.usageRank == ["x": 0])
        let fresh = store(offline, defaults: testDefaults())
        await fresh.refreshWeeklyUsage()
        #expect(fresh.weeklyUsage.isEmpty)
        #expect(fresh.usageRank.isEmpty)
    }

    @Test func anEmptyAnswerKeepsTheCachedUsage() async {
        let defaults = testDefaults()
        await store(FakeSource(ids: ["x"]), defaults: defaults).refreshWeeklyUsage(now: Date(timeIntervalSince1970: 0))
        let empty = FakeSource(ids: [])
        let s = store(empty, defaults: defaults)
        await s.refreshWeeklyUsage(now: Date(timeIntervalSince1970: 7 * 3600))
        #expect(empty.callCount == 1)
        #expect(s.usageRank == ["x": 0])
    }

    @Test func savedDataThatDoesNotReadBackIsIgnored() {
        let defaults = testDefaults()
        defaults.set(Data("not json".utf8), forKey: "models.weeklyUsage.v1")
        #expect(WeeklyUsageCache(defaults: defaults).load().isEmpty)
        #expect(!WeeklyUsageCache(defaults: defaults).isFresh(now: Date()))
    }

    @Test func refreshingModelsAlsoRefreshesTheUsage() async {
        let source = FakeSource(ids: ["a"])
        let s = store(source, defaults: testDefaults())
        await s.refresh()
        #expect(s.usageRank == ["a": 0])
    }
}
