import Foundation
import Testing
@testable import AnyRouter

/// Filter combinations of both tabs, and that each tab remembers its own.
struct ModelFilterTests {
    private let models: [ModelDescriptor] = [
        cloudModel("anyrouter/auto", name: "AnyRouter Auto", input: 0, output: 0, billing: .free, context: 4_194_304, vision: true),
        cloudModel("openai/gpt-5", name: "GPT-5", input: Decimal(string: "1.25"), output: 10, context: 400_000, vision: true, reasoning: true),
        cloudModel("openai/gpt-mini", name: "GPT Mini", input: Decimal(string: "0.25"), output: 2, context: 128_000),
        cloudModel("anthropic/claude-opus", name: "Claude Opus", input: 15, output: 75, context: 200_000, reasoning: true),
        cloudModel("google/flash", name: "Flash", input: Decimal(string: "0.1"), output: Decimal(string: "0.4"), context: 32_000, vision: true),
        cloudModel("vendor/freebie", name: "Freebie", input: 0, output: 0, billing: .free, context: 8192),
        cloudModel("vendor/locked", name: "Locked", availability: .needsKey, context: 1_000_000, vision: true),
        cloudModel("vendor/unpriced", name: "Unpriced", input: nil, output: nil, context: 100_000),
    ]

    private func names(_ filter: ModelFilter, query: String = "") -> [String] {
        CloudListLogic.arrange(
            models: models, query: query, sort: .name, usageRank: [:], showUnusable: true, filter: filter
        ).rest.map(\.displayName)
    }

    @Test func theDefaultHidesModelsThatNeedAKey() {
        #expect(!names(ModelFilter()).contains("Locked"))
        #expect(names(ModelFilter(hideNeedsKey: false)).contains("Locked"))
        #expect(!ModelFilter().isActive)
        #expect(!ModelFilter(hideNeedsKey: false).isActive, "no control sets it, so it never shows as an active filter")
    }

    @Test func aSearchStillFindsModelsThatNeedAKey() {
        #expect(names(ModelFilter(), query: "locked") == ["Locked"])
    }

    @Test func freeOnlyKeepsFreeModels() {
        #expect(names(ModelFilter(freeOnly: true)) == ["AnyRouter Auto", "Freebie"])
    }

    @Test func capabilitiesNarrowTheList() {
        #expect(names(ModelFilter(vision: true)) == ["AnyRouter Auto", "Flash", "GPT-5"])
        #expect(names(ModelFilter(reasoning: true)) == ["Claude Opus", "GPT-5"])
        #expect(names(ModelFilter(vision: true, reasoning: true)) == ["GPT-5"])
    }

    @Test func toolsFollowTheCapabilityTag() {
        var withTools = cloudModel("x/tooly", name: "Tooly")
        withTools.capabilities.insert("tools")
        let list = CloudListLogic.arrange(
            models: models + [withTools], query: "", sort: .name, usageRank: [:], showUnusable: true,
            filter: ModelFilter(tools: true)).rest.map(\.displayName)
        #expect(list == ["Tooly"])
    }

    @Test func longContextMeansAtLeast128KTokens() {
        #expect(names(ModelFilter(longContext: true)) == ["AnyRouter Auto", "Claude Opus", "GPT Mini", "GPT-5"])
    }

    @Test func maxInputPriceCapsThePricePerMillion() {
        // Free models always pass; a model with no price cannot be proven cheap, so it is out.
        #expect(names(ModelFilter(maxInputPrice: .upTo1)) == ["AnyRouter Auto", "Flash", "Freebie", "GPT Mini"])
        #expect(names(ModelFilter(maxInputPrice: .upTo5)) == ["AnyRouter Auto", "Flash", "Freebie", "GPT Mini", "GPT-5"])
        #expect(names(ModelFilter(maxInputPrice: .any)).contains("Claude Opus"))
    }

    @Test func providersAreMultiSelect() {
        #expect(names(ModelFilter(providers: ["openai"])) == ["GPT Mini", "GPT-5"])
        #expect(names(ModelFilter(providers: ["openai", "google"])) == ["Flash", "GPT Mini", "GPT-5"])
    }

    @Test func filtersCombine() {
        let filter = ModelFilter(vision: true, maxInputPrice: .upTo5, providers: ["openai", "google", "anyrouter"])
        #expect(names(filter) == ["AnyRouter Auto", "Flash", "GPT-5"])
        #expect(filter.activeCount == 3) // vision, price, providers
    }

    @Test func activeCountIgnoresTheDefaults() {
        #expect(ModelFilter().activeCount == 0)
        #expect(ModelFilter(freeOnly: true, vision: true, tools: true, reasoning: true, longContext: true,
                            maxInputPrice: .upTo1, providers: ["a"], hideNeedsKey: false).activeCount == 7)
    }

    @Test func theProviderListCountsModelsAndSortsByName() {
        let providers = ModelFilter.providers(in: models)
        #expect(providers.map(\.name) == ["anthropic", "anyrouter", "google", "openai", "vendor"])
        #expect(providers.first { $0.name == "openai" }?.count == 2)
    }

    @Test func nothingMatchingGivesAnEmptyList() {
        #expect(names(ModelFilter(freeOnly: true, reasoning: true)).isEmpty)
    }

    // MARK: Local tab

    private let gguf = localModel("gguf/org/repo/file-Q4_K_M.gguf")
    private let mlx = localModel("mlx/org/repo", source: .mlx)
    private let apple = testModel(id: "apple/foundation", source: .apple)
    private let appleOff = testModel(id: "apple/foundation", source: .apple, installed: false)

    @Test func localEngineFilter() {
        #expect(LocalFilter(engine: .gguf).matches(gguf, fit: nil))
        #expect(!LocalFilter(engine: .gguf).matches(mlx, fit: nil))
        #expect(LocalFilter(engine: .mlx).matches(mlx, fit: nil))
        #expect(LocalFilter(engine: .apple).matches(apple, fit: nil))
        #expect(!LocalFilter(engine: .apple).matches(gguf, fit: nil))
        #expect(LocalFilter(engine: .any).matches(gguf, fit: nil))
    }

    @Test func fitsThisDeviceKeepsOnlyModelsThatRunWell() {
        let filter = LocalFilter(fitsOnly: true)
        #expect(filter.matches(gguf, fit: .fits))
        #expect(!filter.matches(gguf, fit: .tight))
        #expect(!filter.matches(gguf, fit: .wontFit))
        #expect(filter.matches(gguf, fit: .unknown)) // no verdict yet, so it is not hidden
        #expect(filter.matches(apple, fit: nil)) // no fit check for Apple Intelligence
    }

    @Test func hideUnavailableDropsAppleWhenItIsOff() {
        #expect(!LocalFilter(hideUnavailable: true).matches(appleOff, fit: nil))
        #expect(LocalFilter(hideUnavailable: true).matches(apple, fit: nil))
        #expect(LocalFilter().matches(appleOff, fit: nil))
    }

    @Test func localActiveCount() {
        #expect(LocalFilter().activeCount == 0)
        #expect(LocalFilter(engine: .gguf, fitsOnly: true, hideUnavailable: true).activeCount == 3)
    }

    // MARK: Persistence

    @Test func eachTabRemembersItsOwnFilters() {
        let defaults = testDefaults()
        let store = PickerFilterStore(defaults: defaults)
        #expect(store.cloud() == ModelFilter())
        #expect(store.local() == LocalFilter())

        store.save(cloud: ModelFilter(freeOnly: true, vision: true, maxInputPrice: .upTo5, providers: ["openai"], hideNeedsKey: false))
        store.save(local: LocalFilter(engine: .mlx, fitsOnly: true))

        let again = PickerFilterStore(defaults: defaults)
        #expect(again.cloud() == ModelFilter(freeOnly: true, vision: true, maxInputPrice: .upTo5, providers: ["openai"], hideNeedsKey: false))
        #expect(again.local() == LocalFilter(engine: .mlx, fitsOnly: true))
        // Changing one tab leaves the other alone.
        again.save(cloud: ModelFilter())
        #expect(again.local().engine == .mlx)
    }

    @Test func unreadableSavedFiltersFallBackToTheDefault() {
        let defaults = testDefaults()
        defaults.set(Data("not json".utf8), forKey: PickerFilterStore.cloudKey)
        #expect(PickerFilterStore(defaults: defaults).cloud() == ModelFilter())
    }
}
