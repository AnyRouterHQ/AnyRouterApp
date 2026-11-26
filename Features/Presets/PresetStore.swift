import Foundation
import Observation

/// Built-in presets from `presets.json` plus the user's own, stored as one JSON file in Application Support.
@MainActor @Observable
final class PresetStore {
    private struct Saved: Codable {
        var custom: [PromptPreset] = []
        var hiddenBuiltIns: Set<String> = []
        /// The person's choice per built-in preset, over its `offerOnPaste` default.
        var pasteChoices: [String: Bool] = [:]

        init(custom: [PromptPreset], hiddenBuiltIns: Set<String>, pasteChoices: [String: Bool]) {
            self.custom = custom
            self.hiddenBuiltIns = hiddenBuiltIns
            self.pasteChoices = pasteChoices
        }

        /// A file saved before a key existed still loads; a decode error would set the whole file aside.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            custom = try container.decode([PromptPreset].self, forKey: .custom)
            hiddenBuiltIns = try container.decode(Set<String>.self, forKey: .hiddenBuiltIns)
            pasteChoices = try container.decodeIfPresent([String: Bool].self, forKey: .pasteChoices) ?? [:]
        }
    }

    private final class Anchor {}

    let builtIns: [PromptPreset]
    private(set) var custom: [PromptPreset] = []
    private(set) var hiddenBuiltIns: Set<String> = []
    private(set) var pasteChoices: [String: Bool] = [:]
    private(set) var saveError: String?
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = PresetStore.defaultURL, builtIns: [PromptPreset]? = nil) {
        self.fileURL = fileURL
        self.builtIns = builtIns ?? PresetStore.bundledOrEmpty()
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            custom = saved.custom
            hiddenBuiltIns = saved.hiddenBuiltIns
            pasteChoices = saved.pasteChoices
        } else {
            keepUnreadableFile()
        }
    }

    /// A file that exists but cannot be decoded is the user's data. Move it aside before the next save would overwrite it.
    private func keepUnreadableFile() {
        let name = fileURL.deletingPathExtension().lastPathComponent + ".unreadable-\(Int(Date().timeIntervalSince1970)).json"
        let aside = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            saveError = "Your presets file could not be read. It was kept as \(name)."
        } catch {
            saveError = "Your presets file could not be read: \(error.localizedDescription)"
        }
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("presets.json")
    }

    /// The built-in presets, or none when the file cannot be read (the UI then shows only the user's own).
    static func bundledOrEmpty(bundle: Bundle? = nil) -> [PromptPreset] {
        do { return try bundled(bundle: bundle) } catch { return [] }
    }

    /// A missing or broken file is a build error, so this throws.
    static func bundled(bundle: Bundle? = nil) throws -> [PromptPreset] {
        let bundle = bundle ?? Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: "presets", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "presets.json is missing from the app bundle."])
        }
        return try JSONDecoder().decode([PromptPreset].self, from: Data(contentsOf: url))
    }

    var customIDs: Set<String> { Set(custom.map(\.id)) }

    /// Any preset by id, a hidden built-in included: a Shortcut that names one keeps working after the user hides it.
    func preset(id: String) -> PromptPreset? { (custom + builtIns).first { $0.id == id } }
    /// Custom presets first, then the visible built-ins.
    var all: [PromptPreset] { custom + builtIns.filter { !hiddenBuiltIns.contains($0.id) } }
    var hasHiddenBuiltIns: Bool { !hiddenBuiltIns.isEmpty }

    @discardableResult
    func add(title: String, prompt: String, category: PromptPreset.Category, symbol: String = "sparkles") -> PromptPreset {
        let preset = PromptPreset(id: "custom-" + UUID().uuidString, title: title, prompt: prompt, category: category, symbol: symbol)
        custom.insert(preset, at: 0)
        save()
        return preset
    }

    func update(_ preset: PromptPreset) {
        guard let index = custom.firstIndex(where: { $0.id == preset.id }) else { return }
        custom[index] = preset
        save()
    }

    func delete(id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    func setBuiltInHidden(_ id: String, hidden: Bool) {
        if hidden { hiddenBuiltIns.insert(id) } else { hiddenBuiltIns.remove(id) }
        save()
    }

    /// Whether this preset is offered when text is pasted. A custom preset carries its own flag; a built-in follows
    /// the person's choice, else its default.
    func offersOnPaste(_ preset: PromptPreset) -> Bool {
        if customIDs.contains(preset.id) { return preset.offerOnPaste }
        return pasteChoices[preset.id] ?? preset.offerOnPaste
    }

    func setOffersOnPaste(_ id: String, _ on: Bool) {
        if let index = custom.firstIndex(where: { $0.id == id }) {
            custom[index].offerOnPaste = on
        } else {
            pasteChoices[id] = on
        }
        save()
    }

    /// The presets to show above the keyboard after a paste: visible ones that are switched on.
    var pasteOffered: [PromptPreset] { all.filter { offersOnPaste($0) } }

    func resetBuiltIns() {
        hiddenBuiltIns = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Saved(custom: custom, hiddenBuiltIns: hiddenBuiltIns, pasteChoices: pasteChoices))
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Could not save presets: \(error.localizedDescription)"
        }
    }
}
