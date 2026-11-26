import Foundation

/// Runs one prompt through an engine and returns the answer, with no chat, no window and no tools. App Intents use it to
/// answer a Shortcut. It follows the same rules as a chat: the default model, and no cloud model while offline.
@MainActor
struct HeadlessChat {
    let registry: EngineRegistry
    let models: ModelStore
    let presets: PresetStore
    var params: @MainActor () -> GenerationParams
    var isOnline: @MainActor () async -> Bool

    /// What the intents use. Tests replace it with scripted engines.
    static var make: @MainActor () -> HeadlessChat = { HeadlessChat(state: .shared) }

    init(state: AppState) {
        registry = state.registry
        models = state.models
        presets = state.presets
        params = { state.settings.generationParams }
        isOnline = { await state.network.currentlyOnline() }
    }

    init(registry: EngineRegistry, models: ModelStore, presets: PresetStore,
         params: @escaping @MainActor () -> GenerationParams = { GenerationParams() },
         isOnline: @escaping @MainActor () async -> Bool = { true }) {
        self.registry = registry
        self.models = models
        self.presets = presets
        self.params = params
        self.isOnline = isOnline
    }

    /// The models that can answer now. The first call waits for the engines to list theirs.
    func usableModels() async -> [ModelDescriptor] {
        if !models.hasLoaded { await models.refresh() }
        return models.models.filter(\.isInstalled)
    }

    /// A preset applied to a text, answered by the model with `modelID` (or the default one).
    func run(presetID: String, choices: [String: String] = [:], text: String, modelID: String? = nil) async throws -> String {
        let text = try HeadlessLogic.cleaned(text)
        guard let preset = presets.preset(id: presetID) else { throw HeadlessError.unknownPreset }
        return try await ask(HeadlessLogic.prompt(preset: preset, choices: choices, text: text), modelID: modelID)
    }

    /// One prompt, one answer.
    func ask(_ prompt: String, modelID: String? = nil) async throws -> String {
        let prompt = try HeadlessLogic.cleaned(prompt)
        let available = await usableModels()
        let model = try HeadlessLogic.resolve(
            requestedID: modelID, models: available, fallback: models.selected, isOnline: await isOnline())
        var answer = ""
        do {
            let stream = registry.engine(for: model).stream(
                model: model, messages: [ChatMessage(role: .user, content: prompt)], params: params())
            for try await delta in stream {
                if case .text(let piece) = delta { answer += piece }
            }
        } catch {
            throw HeadlessError.failed(model: model.shortName, reason: error.localizedDescription)
        }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadlessError.empty(model: model.shortName) }
        return trimmed
    }
}
