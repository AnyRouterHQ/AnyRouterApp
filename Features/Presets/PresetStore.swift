import Foundation
import Observation

/// Built-in presets from `presets.json` plus the user's own, stored as one JSON file in Application Support.
@MainActor @Observable
final class PresetStore {
    private struct Saved: Codable {
        var custom: [PromptPreset] = []
        var hiddenBuiltIns: Set<String> = []
    }

    private final class Anchor {}

    let builtIns: [PromptPreset]
    private(set) var custom: [PromptPreset] = []
    private(set) var hiddenBuiltIns: Set<String> = []
    private(set) var saveError: String?
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = PresetStore.defaultURL, builtIns: [PromptPreset]? = nil) {
        self.fileURL = fileURL
        self.builtIns = builtIns ?? ((try? PresetStore.bundled()) ?? [])
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            custom = saved.custom
            hiddenBuiltIns = saved.hiddenBuiltIns
        }
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("presets.json")
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

    func resetBuiltIns() {
        hiddenBuiltIns = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Saved(custom: custom, hiddenBuiltIns: hiddenBuiltIns))
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Could not save presets: \(error.localizedDescription)"
        }
    }
}
