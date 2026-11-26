import Foundation
import SwiftData
import Testing
import UIKit
@testable import AnyRouter

@MainActor
struct PresetTests {
    private func sample(_ n: Int) -> [PromptPreset] {
        (0..<n).map { PromptPreset(id: "p\($0)", title: "T\($0)", prompt: "Prompt \($0)",
                                   category: $0.isMultiple(of: 2) ? .learn : .code, symbol: "sparkles") }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString).json")
    }

    @Test func bundledPresetsAreUsable() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        #expect(items.count >= 12)
        #expect(Set(items.map(\.id)).count == items.count)
        for item in items {
            #expect(!item.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(item.id) title")
            #expect(!item.prompt.trimmingCharacters(in: .whitespaces).isEmpty, "\(item.id) prompt")
            #expect(UIImage(systemName: item.symbol) != nil, "\(item.id) symbol \(item.symbol)")
        }
        #expect(Set(items.map(\.category)) == Set(PromptPreset.Category.allCases))
    }

    @Test func categoryFilterAndSearch() {
        let items = sample(6)
        #expect(PresetLogic.filter(items, category: .code).allSatisfy { $0.category == .code })
        #expect(PresetLogic.filter(items, category: nil).count == 6)
        #expect(PresetLogic.filter(items, category: nil, query: "prompt 3").map(\.id) == ["p3"])
        #expect(PresetLogic.filter(items, category: .learn, query: "prompt 3").isEmpty)
    }

    @Test func dailyShuffleIsDeterministicAndSaltChangesIt() {
        let items = sample(12)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let seed = PresetLogic.daySeed(for: day)
        #expect(PresetLogic.shuffled(items, seed: seed) == PresetLogic.shuffled(items, seed: seed))
        #expect(PresetLogic.shuffled(items, seed: seed) != PresetLogic.shuffled(items, seed: seed &+ 1))
        #expect(PresetLogic.daySeed(for: day) != PresetLogic.daySeed(for: day.addingTimeInterval(86_400 * 2)))
    }

    @Test func customPresetsStayFirstInFeatured() {
        let items = sample(10)
        let featured = PresetLogic.featured(items, customIDs: ["p7"], category: nil, seed: 3, limit: 4)
        #expect(featured.first?.id == "p7")
        #expect(featured.count == 4)
    }

    @Test func anUnreadablePresetsFileIsKeptNotOverwritten() throws {
        let url = tempURL()
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: url)
        let store = PresetStore(fileURL: url, builtIns: sample(2))
        #expect(store.custom.isEmpty)
        #expect(store.saveError != nil)
        store.add(title: "Mine", prompt: "Prompt", category: .write)
        let siblings = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(url.deletingPathExtension().lastPathComponent + ".unreadable-") }
        #expect(siblings.count == 1)
        #expect(try Data(contentsOf: siblings[0]) == garbage)
        #expect(PresetStore(fileURL: url, builtIns: sample(2)).custom.map(\.title) == ["Mine"])
    }

    @Test func customCRUDPersistsAcrossReload() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: sample(3))
        let added = store.add(title: "Mine", prompt: "Do it", category: .write)
        var edited = added
        edited.title = "Mine 2"
        store.update(edited)
        store.setBuiltInHidden("p1", hidden: true)

        let reloaded = PresetStore(fileURL: url, builtIns: sample(3))
        #expect(reloaded.custom.map(\.title) == ["Mine 2"])
        #expect(reloaded.all.first?.id == added.id)
        #expect(!reloaded.all.contains { $0.id == "p1" })

        reloaded.delete(id: added.id)
        reloaded.resetBuiltIns()
        let again = PresetStore(fileURL: url, builtIns: sample(3))
        #expect(again.custom.isEmpty)
        #expect(again.all.count == 3)
    }

    @Test func tapFillsComposerAndSendNowSends() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        let preset = sample(1)[0]

        vm.usePreset(preset)
        #expect(vm.input == preset.prompt)
        #expect(vm.focusTick == 1)
        #expect(vm.messages.isEmpty)

        vm.input = ""
        await vm.sendNow(preset)?.value
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        #expect(vm.messages.first?.content == preset.prompt)
        #expect(vm.input.isEmpty)
    }
}
