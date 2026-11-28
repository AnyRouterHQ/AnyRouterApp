import Foundation
import Testing
@testable import AnyRouter

/// Tab, sort and filter combinations of the AnyRouter tab, with a fixture of the server's usage order.
struct CloudListLogicTests {
    private let models: [ModelDescriptor] = [
        cloudModel("anyrouter/auto", name: "AnyRouter Auto", input: 0, output: 0, billing: .free, created: 100),
        cloudModel("anyrouter/free", name: "AnyRouter Free", input: 0, output: 0, billing: .free, created: 100),
        cloudModel("anyrouter/byok", name: "AnyRouter BYOK", created: 100),
        cloudModel("anthropic/claude-sonnet", name: "Claude Sonnet", input: 3, output: 15, created: 300),
        cloudModel("openai/gpt-mini", name: "GPT Mini", input: Decimal(string: "0.15"), output: Decimal(string: "0.6"), created: 500),
        cloudModel("google/gemini-flash", name: "Gemini Flash", input: Decimal(string: "0.1"), output: Decimal(string: "0.4"), created: 400),
        cloudModel("vendor/freebie", name: "Freebie", input: 0, output: 0, billing: .free, created: 200),
        cloudModel("vendor/locked", name: "Locked", availability: .needsKey, created: 600),
        cloudModel("vendor/nopricing", name: "No Pricing", input: nil, output: nil, created: nil),
    ]

    // Server order: most used first. Models missing here sort after the ranked ones.
    private let rank: [String: Int] = [
        "openai/gpt-mini": 0, "anthropic/claude-sonnet": 1, "vendor/locked": 2, "google/gemini-flash": 3,
    ]

    private func names(
        _ sort: PickerSort, query: String = "", rank: [String: Int]? = nil, unusable: Bool = true,
        filter: ModelFilter = ModelFilter()
    ) -> [String] {
        CloudListLogic.arrange(
            models: models, query: query, sort: sort, usageRank: rank ?? self.rank, showUnusable: unusable, filter: filter
        ).rest.map(\.displayName)
    }

    @Test func topUsageFollowsTheServerOrderWithPresetsAmongTheOthersAndUnusableLast() {
        #expect(names(.topUsage) == [
            "GPT Mini", "Claude Sonnet", "Gemini Flash", // usable and ranked
            "AnyRouter Auto", "AnyRouter Free", "Freebie", "No Pricing", // usable, not ranked: A-Z, presets get no lead
            "Locked", // needs a key: after every usable model, still listed
        ])
        #expect(names(.topUsage, rank: ["openai/gpt-mini": 0, "anyrouter/free": 1]).prefix(3) == ["GPT Mini", "AnyRouter Free", "AnyRouter Auto"])
    }

    @Test func offlineWithoutAUsageOrderFallsBackToNameOrder() {
        let offline = names(.topUsage, rank: [:])
        #expect(offline == [
            "AnyRouter Auto", "AnyRouter Free",
            "Claude Sonnet", "Freebie", "Gemini Flash", "GPT Mini", "No Pricing", "Locked",
        ])
    }

    @Test func newestSortsByCreationDateNewestFirst() {
        #expect(names(.newest) == [
            "GPT Mini", "Gemini Flash", "Claude Sonnet", "Freebie", "AnyRouter Auto", "AnyRouter Free", "No Pricing", "Locked",
        ])
    }

    @Test func cheapestSortsByOutputThenInputPriceWithUnknownPricesLast() {
        #expect(names(.cheapest) == [
            "AnyRouter Auto", "AnyRouter Free", "Freebie", "Gemini Flash", "GPT Mini", "Claude Sonnet", "No Pricing", "Locked",
        ])
    }

    @Test func freeKeepsOnlyFreeModelsInUsageOrder() {
        #expect(names(.free) == ["AnyRouter Auto", "AnyRouter Free", "Freebie"])
    }

    @Test func nameSortIsAlphabetical() {
        #expect(names(.name) == [
            "AnyRouter Auto", "AnyRouter Free", "Claude Sonnet", "Freebie", "Gemini Flash", "GPT Mini", "No Pricing", "Locked",
        ])
    }

    @Test func byokRouterIsHiddenButSearchable() {
        #expect(!names(.topUsage).contains("AnyRouter BYOK"))
        #expect(names(.topUsage, query: "byok") == ["AnyRouter BYOK"])
    }

    @Test func searchStillFindsUnusableModelsAndMatchesProviderAndId() {
        #expect(names(.topUsage, query: "locked") == ["Locked"])
        #expect(names(.topUsage, query: "anthropic") == ["Claude Sonnet"])
        #expect(names(.topUsage, query: "gemini-flash") == ["Gemini Flash"])
    }

    @Test func signedOutShowsNothingToPickFrom() {
        let signedOut = models.map { model -> ModelDescriptor in var copy = model; copy.isInstalled = false; return copy }
        let list = CloudListLogic.arrange(models: signedOut, query: "", sort: .topUsage, usageRank: rank, showUnusable: false)
        #expect(list.isEmpty)
    }

    @Test func topPicksLeadAndAreNotRepeatedBelow() {
        let picks = [models[0], models[3]]
        let list = CloudListLogic.arrange(
            models: models, query: "", sort: .topUsage, usageRank: rank, showUnusable: true, picks: picks)
        #expect(list.topPicks.map(\.displayName) == ["AnyRouter Auto", "Claude Sonnet"])
        #expect(!list.rest.contains { $0.displayName == "Claude Sonnet" })
        #expect(list.rest.first?.displayName == "GPT Mini")
    }

    @Test func searchingHidesTopPicks() {
        let list = CloudListLogic.arrange(
            models: models, query: "gpt", sort: .topUsage, usageRank: rank, showUnusable: true, picks: [models[0]])
        #expect(list.topPicks.isEmpty)
        #expect(list.rest.map(\.displayName) == ["GPT Mini"])
    }

    @Test func theSheetOpensOnTheTabOfTheCurrentModel() {
        #expect(PickerTab.tab(for: models[0]) == .anyrouter)
        #expect(PickerTab.tab(for: testModel(id: "apple/foundation", source: .apple)) == .local)
        #expect(PickerTab.tab(for: localModel("gguf/o/r/f.gguf")) == .local)
        #expect(PickerTab.tab(for: nil) == .local)
    }

    @Test func topThisWeekRowsShowTheirRankInRankingOrder() {
        let ranking = ["openai/gpt-mini", "anthropic/claude-sonnet", "google/gemini-flash"].enumerated().map {
            ModelUsage(id: $1, rank: $0 + 1, tokens: 1000 * (3 - $0), requests: 10)
        }
        let usage = Dictionary(uniqueKeysWithValues: ranking.map { ($0.id, $0) })
        let places = Dictionary(uniqueKeysWithValues: ranking.enumerated().map { ($1.id, $0) })
        let list = CloudListLogic.arrange(
            models: models, query: "", sort: .topUsage, usageRank: places, showUnusable: false)
        let rows = list.rest.map { model in
            PickerRow.make(model, usage: CloudListLogic.rowUsage(of: model, sort: .topUsage, in: usage))
        }
        let ranked = rows.filter { $0.rankText != nil }
        #expect(ranked.map(\.title) == ["GPT Mini", "Claude Sonnet", "Gemini Flash"])
        #expect(ranked.compactMap(\.rankText) == ["#1", "#2", "#3"])
        #expect(rows.first { $0.title == "Freebie" }?.rankText == nil, "a model without traffic has no rank")
    }

    @Test func onlyTheTopThisWeekSortShowsUsageOnTheRows() {
        let mini = models[4]
        let usage = [mini.wireID: ModelUsage(id: mini.wireID, rank: 1, tokens: 5000, requests: 40)]
        #expect(CloudListLogic.rowUsage(of: mini, sort: .topUsage, in: usage)?.rank == 1)
        for sort in [PickerSort.newest, .cheapest, .free, .name] {
            #expect(CloudListLogic.rowUsage(of: mini, sort: sort, in: usage) == nil)
        }
        #expect(CloudListLogic.rowUsage(of: models[3], sort: .topUsage, in: usage) == nil)
    }
}
