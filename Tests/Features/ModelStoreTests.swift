import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct ModelStoreTests {
    private func store(models: [ModelDescriptor], defaults: UserDefaults) async -> ModelStore {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: models))
        let store = ModelStore(registry: registry, defaults: defaults)
        await store.refresh()
        return store
    }

    @Test func selectionFallsBackToFirstInstalledModel() async {
        let s = await store(models: [testModel(id: "a", installed: false), testModel(id: "b")], defaults: testDefaults())
        #expect(s.selected?.id == "b")
    }

    @Test func choiceIsPersistedAcrossStores() async {
        let defaults = testDefaults()
        let first = await store(models: [testModel(id: "a"), testModel(id: "b")], defaults: defaults)
        first.select(first.models[1])
        let second = await store(models: [testModel(id: "a"), testModel(id: "b")], defaults: defaults)
        #expect(second.selected?.id == "b")
    }

    @Test func uninstalledModelIsNotSelectedByThreadRestore() async {
        let s = await store(models: [testModel(id: "a"), testModel(id: "b", installed: false)], defaults: testDefaults())
        s.select(modelID: "b")
        #expect(s.selected?.id == "a")
    }

    @Test func withoutASavedPickTheSignedInDefaultIsAutoNotTheFirstCloudModel() async {
        let cloud = { (wire: String) in testModel(id: "anyrouter/\(wire)", source: .anyrouter) }
        // The API lists byok first; it must not become the default.
        let list = [cloud("anyrouter/byok"), cloud("anyrouter/coding"), cloud("anyrouter/auto"), testModel(id: "apple/foundation")]
        let s = await store(models: list, defaults: testDefaults())
        #expect(s.selected?.id == ModelDescriptor.autoRouterID)
    }

    @Test func aSavedPickThatStopsWorkingFallsBackToThePolicy() async {
        let defaults = testDefaults()
        let signedIn = [testModel(id: "anyrouter/openai/gpt", source: .anyrouter), testModel(id: "apple/foundation")]
        let first = await store(models: signedIn, defaults: defaults)
        first.select(signedIn[0])
        let signedOut = [testModel(id: "anyrouter/openai/gpt", source: .anyrouter, installed: false), signedIn[1]]
        let second = await store(models: signedOut, defaults: defaults)
        #expect(second.selected?.id == "apple/foundation")
    }

    @Test func resolveFlagsAnUnusablePreferenceOnlyAfterModelsLoaded() async {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: [testModel(id: "a")]))
        let s = ModelStore(registry: registry, defaults: testDefaults())
        #expect(s.resolve(preferred: "gone").preferredUnavailable == false)
        await s.refresh()
        #expect(s.resolve(preferred: "gone").preferredUnavailable)
        #expect(s.resolve(preferred: "gone").model?.id == "a")
        #expect(s.resolve(preferred: "a") == .init(model: testModel(id: "a"), preferredUnavailable: false))
        #expect(s.resolve(preferred: nil).preferredUnavailable == false)
    }
}
