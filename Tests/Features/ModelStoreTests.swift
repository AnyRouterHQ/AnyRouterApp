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
}
