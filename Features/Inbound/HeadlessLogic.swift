import Foundation

/// Why a headless run (a Shortcuts action that answers without opening the app) could not give an answer. Each message
/// says what to do, because a Shortcut shows it as is.
enum HeadlessError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    case noText
    case unknownPreset
    case noModel
    case unavailable(String)
    case offline(String)
    case failed(model: String, reason: String)
    case empty(model: String)

    var message: String {
        switch self {
        case .noText: "There is no text to work on."
        case .unknownPreset: "That preset no longer exists. Pick another one."
        case .noModel: "No model is ready. Open AnyRouter and choose one."
        case .unavailable(let id): "The model \(id) is not available. Open AnyRouter to check it."
        case .offline(let message): message
        case .failed(let model, let reason): "\(model) could not answer: \(reason)"
        case .empty(let model): "\(model) returned no text."
        }
    }

    var errorDescription: String? { message }
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

/// The choices a headless run makes: which model answers and what the prompt is. Pure, so it is tested without engines.
enum HeadlessLogic {
    /// An asked-for model is used as it is, or the run fails: offline, a cloud model is refused with the name of a model on
    /// the device. Without one, the app's default answers, and offline a cloud default gives way to a model on the device.
    static func resolve(requestedID: String?, models: [ModelDescriptor], fallback: ModelDescriptor?,
                        isOnline: Bool) throws -> ModelDescriptor {
        let suggestion = OfflineLogic.suggestedModel(in: models)
        if let requestedID {
            guard let requested = models.first(where: { $0.id == requestedID && $0.isInstalled }) else {
                throw HeadlessError.unavailable(requestedID)
            }
            if !isOnline, OfflineLogic.needsNetwork(requested) {
                throw HeadlessError.offline(OfflineLogic.modelMessage(for: requested, suggestion: suggestion))
            }
            return requested
        }
        guard let fallback else { throw HeadlessError.noModel }
        if isOnline || !OfflineLogic.needsNetwork(fallback) { return fallback }
        guard let local = suggestion else {
            throw HeadlessError.offline(OfflineLogic.modelMessage(for: fallback, suggestion: nil))
        }
        return local
    }

    /// The picks for a preset's options, by option id and choice id. An option the preset does not have is ignored, and an
    /// unknown choice keeps the default.
    static func selection(for preset: PromptPreset, choices: [String: String]) -> PresetSelection {
        var selection = PresetSelection()
        for option in preset.options ?? [] {
            if let choice = choices[option.id] { selection.pick(choice, for: option) }
        }
        return selection
    }

    /// The prompt for a preset run on a text: the preset's words, then the text.
    static func prompt(preset: PromptPreset, choices: [String: String], text: String) -> String {
        PresetOptionsLogic.composerText(preset, selection: selection(for: preset, choices: choices), message: text)
    }

    static func cleaned(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadlessError.noText }
        return trimmed
    }
}
