import Foundation
import Observation

/// The voice engines of the app and which one answers. The System engines are always there; a downloaded model is used
/// only when it is installed, selected, and covers the language (`VoiceRouting`). Engines for downloaded models are
/// registered by kind at launch and built on first use.
@MainActor @Observable
final class VoiceHub {
    typealias SpeechToTextFactory = @MainActor (VoiceModel, URL) -> (any SpeechToText)?
    typealias TextToSpeechFactory = @MainActor (VoiceModel, URL) -> (any TextToSpeech)?

    let settings: VoiceSettings
    let downloader: VoiceModelDownloader

    @ObservationIgnored private let loadCatalog: () throws -> [VoiceModel]
    @ObservationIgnored private var cachedCatalog: [VoiceModel]?
    @ObservationIgnored private let makeSystemSTT: @MainActor () -> any SpeechToText
    @ObservationIgnored private let makeSystemTTS: @MainActor () -> any TextToSpeech
    @ObservationIgnored private var systemSTTEngine: (any SpeechToText)?
    @ObservationIgnored private var systemTTSEngine: (any TextToSpeech)?
    @ObservationIgnored private var sttFactories: [VoiceEngineKind: SpeechToTextFactory] = [:]
    @ObservationIgnored private var ttsFactories: [VoiceEngineKind: TextToSpeechFactory] = [:]
    @ObservationIgnored private var sttEngines: [String: any SpeechToText] = [:]
    @ObservationIgnored private var ttsEngines: [String: any TextToSpeech] = [:]

    init(
        settings: VoiceSettings = VoiceSettings(), downloader: VoiceModelDownloader = VoiceModelDownloader(),
        catalog: @escaping () throws -> [VoiceModel] = { try BundledVoiceCatalog.load() },
        systemSTT: @escaping @MainActor () -> any SpeechToText = { SystemSpeechToText() },
        systemTTS: @escaping @MainActor () -> any TextToSpeech = { SystemTextToSpeech() }
    ) {
        self.settings = settings
        self.downloader = downloader
        loadCatalog = catalog
        makeSystemSTT = systemSTT
        makeSystemTTS = systemTTS
    }

    // MARK: Catalog

    /// The bundled catalog, read once. It is tested to decode, so a failure here is a broken build and shows as an empty list.
    var catalog: [VoiceModel] {
        if let cachedCatalog { return cachedCatalog }
        let loaded = (try? loadCatalog()) ?? []
        cachedCatalog = loaded
        return loaded
    }

    /// The System row first, then the downloads by catalog order.
    func models(_ kind: VoiceModelKind) -> [VoiceModel] {
        [.system(kind)] + catalog.filter { $0.kind == kind }.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
    }

    func recommended(_ kind: VoiceModelKind, memory: DeviceMemory = .current()) -> VoiceModel? {
        VoiceFit.recommended(catalog, kind: kind, memory: memory)
    }

    /// The speech model the voice button offers before it listens, or nil to listen at once (`VoiceModeGateLogic`).
    func voiceModeOffer(memory: DeviceMemory = .current()) -> VoiceModel? {
        VoiceModeGateLogic.offer(
            recommended: recommended(.stt, memory: memory),
            installedSTT: !downloader.installedIDs(in: models(.stt)).isEmpty,
            declined: settings.voiceModeDeclined)
    }

    // MARK: Selection

    func selectedID(_ kind: VoiceModelKind) -> String {
        (kind == .stt ? settings.selectedSTT : settings.selectedTTS) ?? VoiceModel.systemID
    }

    func select(_ model: VoiceModel) {
        let id = model.isSystem ? nil : model.id
        if model.kind == .stt { settings.selectedSTT = id } else { settings.selectedTTS = id }
    }

    func isSelected(_ model: VoiceModel) -> Bool { selectedID(model.kind) == model.id }

    // MARK: Engines

    func register(speechToText factory: @escaping SpeechToTextFactory, for kind: VoiceEngineKind) { sttFactories[kind] = factory }
    func register(textToSpeech factory: @escaping TextToSpeechFactory, for kind: VoiceEngineKind) { ttsFactories[kind] = factory }

    func choice(_ kind: VoiceModelKind, language: VoiceLanguage?) -> VoiceChoice {
        VoiceRouting.choose(
            kind: kind, language: language, selectedID: kind == .stt ? settings.selectedSTT : settings.selectedTTS,
            installed: downloader.installedIDs(in: catalog), catalog: catalog)
    }

    /// The engine to dictate with and why. `language` is the one the user forced, nil to detect.
    func speechToText(for language: VoiceLanguage?) -> (engine: any SpeechToText, choice: VoiceChoice) {
        let choice = choice(.stt, language: language)
        if case .model(let model) = choice {
            if let engine = speechToTextEngine(for: model) { return (engine, choice) }
            return (systemSpeechToText, .system(nil))
        }
        return (systemSpeechToText, choice)
    }

    func textToSpeech(for language: VoiceLanguage) -> (engine: any TextToSpeech, choice: VoiceChoice) {
        let choice = choice(.tts, language: language)
        if case .model(let model) = choice {
            if let engine = textToSpeechEngine(for: model) { return (engine, choice) }
            return (systemTextToSpeech, .system(nil))
        }
        return (systemTextToSpeech, choice)
    }

    var systemSpeechToText: any SpeechToText {
        if let systemSTTEngine { return systemSTTEngine }
        let engine = makeSystemSTT()
        systemSTTEngine = engine
        return engine
    }

    var systemTextToSpeech: any TextToSpeech {
        if let systemTTSEngine { return systemTTSEngine }
        let engine = makeSystemTTS()
        systemTTSEngine = engine
        return engine
    }

    /// Drops a model's loaded engine, so its memory is freed and a deleted model is not used again.
    func forget(_ model: VoiceModel) {
        sttEngines[model.id] = nil
        ttsEngines[model.id] = nil
    }

    private func speechToTextEngine(for model: VoiceModel) -> (any SpeechToText)? {
        if let engine = sttEngines[model.id] { return engine }
        guard let factory = sttFactories[model.engine],
              let engine = factory(model, downloader.storage.directory(for: model.id)) else { return nil }
        sttEngines[model.id] = engine
        return engine
    }

    private func textToSpeechEngine(for model: VoiceModel) -> (any TextToSpeech)? {
        if let engine = ttsEngines[model.id] { return engine }
        guard let factory = ttsFactories[model.engine],
              let engine = factory(model, downloader.storage.directory(for: model.id)) else { return nil }
        ttsEngines[model.id] = engine
        return engine
    }
}
