import AppIntents

/// A model Shortcuts can list: Apple's, the downloaded ones and the AnyRouter ones that are ready.
struct ModelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Model")
    static let defaultQuery = ModelEntityQuery()

    let id: String
    let name: String
    let kind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kind)")
    }

    init(_ model: ModelDescriptor) {
        id = model.id
        name = model.shortName
        kind = switch model.source {
        case .apple: "Apple Intelligence"
        case .gguf, .mlx: "On this device"
        case .anyrouter: "AnyRouter"
        }
    }
}

struct ModelEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ModelEntity] {
        await Self.usable().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ModelEntity] {
        await Self.usable()
    }

    @MainActor
    static func usable() async -> [ModelEntity] {
        await HeadlessChat.make().usableModels().map(ModelEntity.init)
    }
}

/// The languages "Translate" offers. The raw values are the choice ids of the shipped Translate preset.
enum TranslationLanguage: String, AppEnum, CaseIterable {
    case english, vietnamese, japanese, korean, chinese, french, spanish, german

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Language")
    static let caseDisplayRepresentations: [TranslationLanguage: DisplayRepresentation] = [
        .english: "English", .vietnamese: "Vietnamese", .japanese: "Japanese", .korean: "Korean",
        .chinese: "Chinese", .french: "French", .spanish: "Spanish", .german: "German",
    ]
}

// The intents below answer the Shortcut with a string and never open the app. They run in the app's process without a
// window, on the same engines as the chat, and refuse a cloud model while the device is offline.

struct RunPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Run preset on text"
    static let description = IntentDescription("Apply a preset to a text and get the answer back, without opening the app.")

    @Parameter(title: "Preset")
    var preset: PresetEntity

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Model")
    var model: ModelEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$preset) on \(\.$text)")
    }

    init() {}

    init(preset: PresetEntity, text: String, model: ModelEntity? = nil) {
        self.preset = preset
        self.text = text
        self.model = model
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let answer = try await HeadlessChat.make().run(presetID: preset.id, text: text, modelID: model?.id)
        return .result(value: answer)
    }
}

struct SummarizeIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize"
    static let description = IntentDescription("Summarize a text and get the summary back, without opening the app.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Model")
    var model: ModelEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$text)")
    }

    init() {}

    init(text: String, model: ModelEntity? = nil) {
        self.text = text
        self.model = model
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let answer = try await HeadlessChat.make().run(presetID: InboundPreset.summarize, text: text, modelID: model?.id)
        return .result(value: answer)
    }
}

struct TranslateIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate"
    static let description = IntentDescription("Translate a text and get the translation back, without opening the app.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Language", default: .english)
    var language: TranslationLanguage

    @Parameter(title: "Model")
    var model: ModelEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$text) to \(\.$language)")
    }

    init() {}

    init(text: String, language: TranslationLanguage, model: ModelEntity? = nil) {
        self.text = text
        self.language = language
        self.model = model
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let answer = try await HeadlessChat.make().run(
            presetID: InboundPreset.translate, choices: ["language": language.rawValue], text: text, modelID: model?.id)
        return .result(value: answer)
    }
}

struct AskWithModelIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask with model"
    static let description = IntentDescription("Ask one model a question and get its answer back, without opening the app.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Model")
    var model: ModelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$model) \(\.$text)")
    }

    init() {}

    init(text: String, model: ModelEntity) {
        self.text = text
        self.model = model
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let answer = try await HeadlessChat.make().ask(text, modelID: model.id)
        return .result(value: answer)
    }
}
