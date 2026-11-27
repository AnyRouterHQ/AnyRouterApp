import Foundation
import Testing
@testable import AnyRouter

/// The @ list tells the reader which plugins are on, and why a plugin or file cannot be chosen for a model without tools.
@MainActor
struct MentionToolStateTests {
    private let sources = [ToolSourceCatalog.device, ToolSourceCatalog.exa, ToolSourceCatalog.deepWiki]

    private func file() -> ChatAttachment {
        ChatAttachment(id: UUID(), kind: .text, filename: "notes.txt", utType: "public.plain-text", byteCount: 3, relativePath: "x/notes.txt")
    }

    @Test func pluginRowsSayOnOrOffAndKeepTheirKind() {
        let rows = ComposerMention.items(sources: sources, files: [], isOn: { $0.id != "deepwiki" })
        #expect(rows.map(\.detail) == ["Plugin · On", "Plugin · On", "Plugin · Off"])
        #expect(rows.allSatisfy(\.isAvailable))
        #expect(rows.map(\.trailing) == ["Plugin", "Plugin", "Plugin"], "the kind itself does not change")
    }

    @Test func rowsWithoutASwitchShowOnlyTheirKind() {
        let rows = ComposerMention.items(sources: [ToolSourceCatalog.exa], files: [])
        #expect(rows.map(\.detail) == ["Plugin"])
    }

    @Test func aModelWithoutToolsDisablesPluginsAndFilesWithTheReasonInWords() {
        let rows = ComposerMention.items(sources: sources, files: [file()], isOn: { _ in true }, unavailableReason: ComposerMention.noToolsReason)
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { !$0.isAvailable })
        #expect(rows.allSatisfy { $0.detail == "This model has no tools" })
    }

    @Test func presetsStayChoosableWhateverTheModel() throws {
        let presets = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let rows = ComposerMention.items(sources: sources, files: [], presets: presets, unavailableReason: ComposerMention.noToolsReason)
        let helpers = rows.filter { if case .preset = $0.kind { true } else { false } }
        #expect(!helpers.isEmpty)
        #expect(helpers.allSatisfy { $0.isAvailable && $0.detail == "Preset" })
    }
}
