import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct PresetMentionTests {
    private func shipped() throws -> [PromptPreset] {
        try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
    }

    @Test func theListOffersPresetsWithPickersAfterThePlugins() throws {
        let exa = MentionItem(kind: .plugin(sourceID: "exa"), title: "Exa", trailing: "Plugin", icon: .symbol("x"))
        let source = ToolSourceCatalog.device
        let rows = ComposerMention.items(sources: [source], files: [], presets: try shipped())
        let presets = rows.filter { if case .preset = $0.kind { true } else { false } }
        #expect(Set(presets.map(\.id)) == ["preset/reply-to-this", "preset/translate", "preset/split-bill"])
        #expect(presets.allSatisfy { $0.trailing == "Preset" })
        #expect(rows.first?.id == "plugin/\(source.id)", "plugins come first")
        #expect(ComposerMention.items(sources: [], files: [], presets: []).isEmpty)
        #expect(exa.forcedSourceID == "exa")
    }

    @Test func aPresetTurnsNoSourceOnAndIsFoundByItsName() throws {
        let rows = ComposerMention.items(sources: [], files: [], presets: try shipped())
        let reply = try #require(rows.first { $0.id == "preset/reply-to-this" })
        #expect(reply.forcedSourceID == nil)
        #expect(ComposerMention.forcedSourceIDs(of: [reply]).isEmpty)
        #expect(ComposerMention.filter(rows, query: "rep").map(\.title) == ["Reply to this"])
    }

    @Test func choosingAPresetOpensItsChoicesWithTheRestOfTheFieldAsTheMessage() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        let reply = try #require(try shipped().first { $0.id == "reply-to-this" })

        vm.input = "Can you come at 5? @rep"
        vm.choosePreset(reply)
        #expect(vm.input == "Can you come at 5?")
        #expect(vm.presetNeedingChoices?.id == "reply-to-this")
        #expect(vm.mentions.isEmpty, "a preset is not a chip")

        vm.presetNeedingChoices = nil
        vm.input = "no at word here"
        vm.choosePreset(reply)
        #expect(vm.input == "no at word here")
        #expect(vm.presetNeedingChoices != nil)
    }
}
