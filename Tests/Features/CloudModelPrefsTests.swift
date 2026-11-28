import Foundation
import Testing
@testable import AnyRouter

/// Stars and hidden models: what they do to a list, and that they survive a relaunch.
struct CloudModelPrefsTests {
    private let models: [ModelDescriptor] = [
        cloudModel("openai/a", name: "Alpha"), cloudModel("openai/b", name: "Bravo"), cloudModel("google/c", name: "Charlie"),
        cloudModel("vendor/locked", name: "Locked", availability: .needsKey), localModel("gguf/o/m/m.gguf"),
    ]

    private func arrange(_ prefs: CloudModelPrefs, query: String = "", picks: [ModelDescriptor] = []) -> CloudList {
        CloudListLogic.arrange(
            models: models, query: query, sort: .name, usageRank: [:], showUnusable: true, picks: picks,
            filter: ModelFilter(hideNeedsKey: false), prefs: prefs)
    }

    // MARK: Marks

    @Test func starringKeepsTheOrderAndTogglesOff() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar("openai/a")
        prefs.toggleStar("google/c")
        #expect(prefs.starred == ["openai/a", "google/c"])
        prefs.toggleStar("openai/a")
        #expect(prefs.starred == ["google/c"])
        #expect(prefs.isStarred(models[2]) && !prefs.isStarred(models[0]))
    }

    @Test func starringAHiddenModelBringsItBackAndHidingAStarredOneDropsTheStar() {
        var prefs = CloudModelPrefs()
        prefs.hide("openai/a")
        prefs.toggleStar("openai/a")
        #expect(!prefs.isHidden(models[0]) && prefs.isStarred(models[0]))
        prefs.hide("openai/a")
        #expect(prefs.isHidden(models[0]) && !prefs.isStarred(models[0]))
        prefs.unhide("openai/a")
        #expect(!prefs.isHidden(models[0]))
    }

    @Test func hiddenModelsAreListedAToZAndCloudOnly() {
        var prefs = CloudModelPrefs()
        prefs.hide("openai/b")
        prefs.hide("google/c")
        prefs.hide("gguf/o/m/m.gguf")
        #expect(prefs.hiddenModels(in: models).map(\.displayName) == ["Bravo", "Charlie"])
    }

    @Test func starredCountIgnoresModelsAnyRouterNoLongerLists() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar("openai/a")
        prefs.toggleStar("gone/model")
        #expect(prefs.starredCount(in: models) == 1)
    }

    // MARK: In a list

    @Test func starredModelsLeadInStarOrderAndAreNotRepeated() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar("google/c")
        prefs.toggleStar("openai/a")
        let list = arrange(prefs, picks: [models[0], models[1]])
        #expect(list.starred.map(\.displayName) == ["Charlie", "Alpha"])
        #expect(list.topPicks.map(\.displayName) == ["Bravo"], "a starred pick is not listed twice")
        #expect(list.rest.map(\.displayName) == ["Locked"])
    }

    @Test func aStarredModelThatCannotBeUsedStaysInTheListInsteadOfLeadingIt() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar("vendor/locked")
        let list = arrange(prefs)
        #expect(list.starred.isEmpty)
        #expect(list.rest.map(\.displayName).contains("Locked"))
    }

    @Test func hiddenModelsLeaveTheListButASearchStillFindsThem() {
        var prefs = CloudModelPrefs()
        prefs.hide("openai/b")
        #expect(!arrange(prefs).rest.map(\.displayName).contains("Bravo"))
        #expect(arrange(prefs, query: "Bravo").rest.map(\.displayName) == ["Bravo"])
        #expect(!arrange(prefs).isEmpty)
    }

    @Test func aSearchIgnoresStarsSoResultsStayInOneList() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar("openai/a")
        let list = arrange(prefs, query: "openai")
        #expect(list.starred.isEmpty)
        #expect(list.rest.map(\.displayName) == ["Alpha", "Bravo"])
    }

    @Test func aListWithOnlyStarredModelsIsNotEmpty() {
        let only = CloudList(topPicks: [], rest: [], starred: [models[0]])
        #expect(!only.isEmpty)
        #expect(CloudList(topPicks: [], rest: []).isEmpty)
    }

    // MARK: Saving

    @Test func prefsRoundTripThroughDefaults() {
        let defaults = testDefaults()
        #expect(CloudModelPrefs.load(from: defaults) == CloudModelPrefs())
        var prefs = CloudModelPrefs()
        prefs.toggleStar("openai/a")
        prefs.hide("google/c")
        prefs.save(to: defaults)
        #expect(CloudModelPrefs.load(from: defaults) == prefs)
    }

    @Test func unreadableSavedDataMeansNoMarksNotACrash() {
        let defaults = testDefaults()
        defaults.set(Data("not json".utf8), forKey: CloudModelPrefs.defaultsKey)
        #expect(CloudModelPrefs.load(from: defaults) == CloudModelPrefs())
    }
}

@MainActor
struct ModelStorePrefsTests {
    @Test func starsAndHiddenModelsSurviveARelaunch() {
        let defaults = testDefaults()
        let first = ModelStore(registry: EngineRegistry(), defaults: defaults)
        let a = cloudModel("openai/a"), b = cloudModel("openai/b"), c = cloudModel("google/c")
        first.toggleStar(a)
        first.toggleStar(c)
        first.hide(b)
        first.hide(c)
        #expect(first.cloudPrefs.starred == ["openai/a"], "hiding drops the star")

        let second = ModelStore(registry: EngineRegistry(), defaults: defaults)
        #expect(second.cloudPrefs == first.cloudPrefs)
        second.unhide(b)
        #expect(second.cloudPrefs.hidden == ["google/c"])
        #expect(ModelStore(registry: EngineRegistry(), defaults: defaults).cloudPrefs.hidden == ["google/c"])
    }

    @Test func theDefaultIsOneModelWhateverItsSource() async {
        let list = [testModel(id: "apple/foundation"), testModel(id: "gguf/o/m/m.gguf", source: .gguf), cloudModel("openai/a")]
        let defaults = testDefaults()
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: list))
        let store = ModelStore(registry: registry, defaults: defaults)
        await store.refresh()
        for model in list {
            store.select(model)
            #expect(store.selected?.id == model.id)
        }
        let again = ModelStore(registry: registry, defaults: defaults)
        await again.refresh()
        #expect(again.selected?.id == "anyrouter/openai/a", "the last pick is the one default, found again after a relaunch")
    }
}
