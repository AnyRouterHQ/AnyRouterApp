import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct VoiceHubTests {
    private struct Rig {
        let hub: VoiceHub
        let system: FakeSpeechToText
        let systemVoice: FakeTextToSpeech
        let root: URL
    }

    /// A model with one file, so a transport has something to fail or hang on. With no files a download just installs.
    private func withFile(_ model: VoiceModel) -> VoiceModel {
        var model = model
        model.files = [VoiceModelFile(path: "a.bin", url: URL(string: "https://example.com/a.bin")!, sizeBytes: 1)]
        return model
    }

    private func rig(catalog: [VoiceModel], transport: ((VoiceModelStorage) -> FakeVoiceTransport)? = nil) -> Rig {
        let system = FakeSpeechToText(id: "system")
        let systemVoice = FakeTextToSpeech(id: "system")
        let root = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString)")
        let storage = VoiceModelStorage(root: root)
        let hub = VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            downloader: VoiceModelDownloader(storage: storage, transport: transport?(storage) ?? InertVoiceTransport()),
            catalog: { catalog }, systemSTT: { system }, systemTTS: { systemVoice })
        return Rig(hub: hub, system: system, systemVoice: systemVoice, root: root)
    }

    private func install(_ model: VoiceModel, in rig: Rig) throws {
        try rig.hub.downloader.storage.writeManifest(VoiceInstalledManifest(id: model.id, files: [], completedAt: Date()))
    }

    private let small = VoiceFixtures.model("whisper-small", detects: true, order: 3)
    private let tiny = VoiceFixtures.model("whisper-tiny", detects: true, weak: ["vi"], order: 1)
    private let voice = VoiceFixtures.model("voice-en", kind: .tts, languages: ["en"], order: 1)

    @Test func theListStartsWithTheSystemRowThenTheCatalogInOrder() {
        let r = rig(catalog: [small, voice, tiny])
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.hub.models(.stt).map(\.id) == ["system", "whisper-tiny", "whisper-small"])
        #expect(r.hub.models(.tts).map(\.id) == ["system", "voice-en"])
        #expect(r.hub.catalog.count == 3)
    }

    @Test func theSystemEnginesAnswerUntilAModelIsInstalledAndSelected() throws {
        let r = rig(catalog: [small])
        defer { try? FileManager.default.removeItem(at: r.root) }
        var factoryCalls = 0
        let whisper = FakeSpeechToText(id: "whisper")
        r.hub.register(speechToText: { _, _ in factoryCalls += 1; return whisper }, for: .whisperKit)

        #expect(r.hub.speechToText(for: nil).engine.id == "system")
        #expect(r.hub.isSelected(.system(.stt)))
        r.hub.select(small)
        #expect(r.hub.isSelected(small) && !r.hub.isSelected(.system(.stt)))
        let notYet = r.hub.speechToText(for: nil)
        #expect(notYet.engine.id == "system" && notYet.choice == .system(.notInstalled))

        try install(small, in: r)
        let chosen = r.hub.speechToText(for: nil)
        #expect(chosen.engine.id == "whisper" && chosen.choice == .model(small))
        _ = r.hub.speechToText(for: .vietnamese)
        #expect(factoryCalls == 1, "the engine is built once")

        r.hub.forget(small)
        _ = r.hub.speechToText(for: nil)
        #expect(factoryCalls == 2)

        r.hub.select(.system(.stt))
        #expect(r.hub.speechToText(for: nil).engine.id == "system")
        #expect(r.hub.selectedID(.stt) == VoiceModel.systemID)
    }

    @Test func aModelThatDoesNotCoverTheLanguageHandsOverToTheSystemVoice() throws {
        let r = rig(catalog: [voice])
        defer { try? FileManager.default.removeItem(at: r.root) }
        let neural = FakeTextToSpeech(id: "neural", supported: [.english])
        r.hub.register(textToSpeech: { _, _ in neural }, for: .moonshine)
        r.hub.select(voice)
        try install(voice, in: r)
        #expect(r.hub.textToSpeech(for: .english).engine.id == "neural")
        let vietnamese = r.hub.textToSpeech(for: .vietnamese)
        #expect(vietnamese.engine.id == "system")
        #expect(vietnamese.choice == .system(.languageNotCovered(.vietnamese)))
        #expect(r.hub.selectedID(.tts) == "voice-en")
    }

    @Test func anEngineKindThatThisBuildLacksFallsBackQuietly() throws {
        let r = rig(catalog: [small, voice])
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.hub.select(small)
        r.hub.select(voice)
        try install(small, in: r)
        try install(voice, in: r)
        #expect(r.hub.speechToText(for: nil).engine.id == "system")
        #expect(r.hub.textToSpeech(for: .english).engine.id == "system")
        r.hub.register(speechToText: { _, _ in nil }, for: .whisperKit)
        r.hub.register(textToSpeech: { _, _ in nil }, for: .moonshine)
        #expect(r.hub.speechToText(for: nil).engine.id == "system")
        #expect(r.hub.textToSpeech(for: .english).engine.id == "system")
    }

    @Test func theEngineIsHandedItsInstallFolder() throws {
        let r = rig(catalog: [small])
        defer { try? FileManager.default.removeItem(at: r.root) }
        var folder: URL?
        r.hub.register(speechToText: { _, url in folder = url; return FakeSpeechToText() }, for: .whisperKit)
        r.hub.select(small)
        try install(small, in: r)
        _ = r.hub.speechToText(for: nil)
        #expect(folder == r.hub.downloader.storage.directory(for: small.id))
    }

    @Test func theSystemEnginesAreBuiltOnFirstUse() {
        var built = 0
        let hub = VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!), catalog: { [] },
            systemSTT: { built += 1; return FakeSpeechToText() }, systemTTS: { FakeTextToSpeech() })
        #expect(built == 0)
        _ = hub.systemSpeechToText
        _ = hub.systemSpeechToText
        #expect(built == 1)
        _ = hub.systemTextToSpeech
    }

    @Test func theRecommendationFollowsTheDevice() {
        let r = rig(catalog: [small, tiny])
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.hub.recommended(.stt, memory: DeviceClass.gb8.memory(.standard))?.id == "whisper-small")
        #expect(r.hub.recommended(.tts, memory: DeviceClass.gb8.memory(.standard)) == nil)
        #expect(r.hub.recommended(.stt, memory: DeviceMemory(budgetBytes: 1, physicalBytes: 1)) == nil)
    }

    /// The voice button offers the recommended speech model once: not when one is installed, nothing fits, or after Not Now.
    @Test func voiceModeOffersTheRecommendedModelUntilOneIsInstalledOrDeclined() throws {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let r = rig(catalog: [small, tiny, voice])
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.hub.voiceModeOffer(memory: gb8)?.id == "whisper-small")
        #expect(r.hub.voiceModeOffer(memory: DeviceMemory(budgetBytes: 1, physicalBytes: 1)) == nil, "nothing fits")

        r.hub.settings.voiceModeDeclined = true
        #expect(r.hub.voiceModeOffer(memory: gb8) == nil, "Not Now: dictate with the System engine")
        r.hub.settings.voiceModeDeclined = false

        try install(tiny, in: r)
        #expect(r.hub.voiceModeOffer(memory: gb8) == nil, "a speech model is already on the phone")
    }

    @Test func voiceModeShowsTheRealDownloadSize() {
        let title = VoiceModeGateLogic.downloadTitle(small)
        #expect(title == "Download (\(ByteCountFormatter.string(fromByteCount: small.sizeBytes, countStyle: .file)))")
        #expect(VoiceModeGateLogic.offer(recommended: small, installedSTT: false, declined: false) == small)
        #expect(VoiceModeGateLogic.offer(recommended: nil, installedSTT: false, declined: false) == nil)
    }

    @Test func aModelChosenBeforeIsOfferedAgainInsteadOfTheRecommendation() {
        #expect(VoiceModeGateLogic.offer(recommended: small, installedSTT: false, declined: false, pending: tiny) == tiny)
        #expect(VoiceModeGateLogic.offer(recommended: small, installedSTT: false, declined: true, pending: tiny) == tiny)
        #expect(VoiceModeGateLogic.offer(recommended: small, installedSTT: true, declined: false, pending: tiny) == nil,
                "once a speech model is installed, Voice Mode starts")
    }

    @Test func theGateNamesTheModelWithItsLanguagesAndSize() {
        let base = VoiceFixtures.model("whisper-base", size: 149_484_796, order: 2)
        let size = ByteCountFormatter.string(fromByteCount: 149_484_796, countStyle: .file)
        #expect(VoiceModeGateLogic.sizeLabel(base) == size)
        #expect(VoiceModeGateLogic.headline(base) == "whisper-base · Many languages · \(size)")
        let english = VoiceFixtures.model("voice-en", languages: ["en"], size: 79_400_740)
        #expect(VoiceModeGateLogic.headline(english).hasPrefix("voice-en · \(VoiceLanguage("en").name) · "))
    }

    /// The picker lists the downloads of the Voice settings list that fit this phone, in its order, never the System row,
    /// a voice (text to speech) or a model that will not fit.
    @Test func theGatePicksFromTheSameModelsAsSettingsThatFitThePhone() {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let huge = VoiceFixtures.model("whisper-huge", detects: true, size: 6_000_000_000, order: 9)
        let r = rig(catalog: [small, voice, huge, tiny])
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(VoiceModeGateLogic.options(r.hub.models(.stt) + r.hub.models(.tts), memory: gb8).map(\.id) == ["whisper-tiny", "whisper-small"])
        #expect(VoiceModeGateLogic.options(r.hub.models(.stt), memory: DeviceMemory(budgetBytes: 1, physicalBytes: 1)).isEmpty)
        #expect(VoiceModeGateLogic.options(r.hub.models(.stt), memory: gb8).contains(where: { $0.id == r.hub.recommended(.stt, memory: gb8)?.id }),
                "the offer is one of the choices")
    }

    @Test func theRecommendedChoiceIsBadgedAndATightOneSaysSo() {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let tight = VoiceFixtures.model("whisper-tight", size: 900_000_000, order: 5)
        #expect(VoiceFit.verdict(tight, memory: gb8) == .tight, "fixture is tight on 8 GB")
        let title = { (model: VoiceModel) in VoiceModeGateLogic.optionTitle(model, recommended: small, memory: gb8) }
        #expect(title(small) == VoiceModeGateLogic.headline(small) + " · Recommended")
        #expect(title(tiny) == VoiceModeGateLogic.headline(tiny))
        #expect(title(tight) == VoiceModeGateLogic.headline(tight) + " · Tight on this device")
        #expect(VoiceModeGateLogic.optionTitle(tiny, recommended: nil, memory: gb8) == VoiceModeGateLogic.headline(tiny))
    }

    /// The path the gate relies on once its cover is gone: the model the person chose (not the recommendation) is the
    /// selected speech model when its download ends, with no view alive to write it.
    @Test func aVoiceModeDownloadThatFinishesIsTheSelectedModelAndReady() async throws {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let r = rig(catalog: [small, tiny])
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.hub.voiceDownload == .idle)
        let task = try #require(r.hub.startVoiceModeDownload(tiny))
        #expect(r.hub.settings.voiceModeTarget == "whisper-tiny")
        #expect(r.hub.voiceDownload.phase == .downloading && r.hub.voiceDownload.modelID == "whisper-tiny")
        #expect(r.hub.voiceModeOffer(memory: gb8)?.id == "whisper-tiny", "opened again, the gate shows this download, not the recommendation")
        await task.value
        #expect(r.hub.settings.selectedSTT == "whisper-tiny")
        #expect(r.hub.settings.voiceModeTarget == nil)
        #expect(r.hub.voiceDownload.phase == .ready && r.hub.readyModelID == "whisper-tiny")
        #expect(r.hub.voiceModeOffer(memory: gb8) == nil, "the next tap goes straight into Voice Mode")
        r.hub.dismissReady()
        #expect(r.hub.voiceDownload == .idle)
    }

    @Test func cancellingTheVoiceModeDownloadForgetsTheChoice() async throws {
        let model = withFile(tiny)
        let r = rig(catalog: [model], transport: { let t = FakeVoiceTransport(storage: $0); t.hangs = true; return t })
        defer { try? FileManager.default.removeItem(at: r.root) }
        let task = try #require(r.hub.startVoiceModeDownload(model))
        await Task.yield()
        r.hub.cancelVoiceModeDownload(model)
        await task.value
        #expect(r.hub.settings.voiceModeTarget == nil && r.hub.settings.selectedSTT == nil)
        #expect(r.hub.voiceDownload == .idle)
    }

    /// A failed download keeps the choice for Try Again, until the person says Not Now.
    @Test func aFailedVoiceModeDownloadCanBeRetriedUntilNotNow() async throws {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let model = withFile(tiny)
        let r = rig(catalog: [model, small], transport: { let t = FakeVoiceTransport(storage: $0); t.fails = true; return t })
        defer { try? FileManager.default.removeItem(at: r.root) }
        await r.hub.startVoiceModeDownload(model)?.value
        #expect(r.hub.voiceDownload.phase == .failed && r.hub.voiceDownload.canRetry)
        #expect(r.hub.settings.voiceModeTarget == "whisper-tiny")
        #expect(r.hub.settings.selectedSTT == nil)
        #expect(r.hub.voiceModeOffer(memory: gb8)?.id == "whisper-tiny", "Try Again is on the gate")
        r.hub.settings.voiceModeDeclined = true
        #expect(r.hub.voiceModeOffer(memory: gb8) == nil, "Not Now dictates with the System engine")
        let again = try #require(r.hub.startVoiceModeDownload(model), "Try Again starts it once more")
        await again.value
        #expect(r.hub.voiceDownload.phase == .failed)
    }

    @Test func aChosenModelThatIsNotInTheSpeechCatalogIsNotOffered() {
        let gb8 = DeviceClass.gb8.memory(.standard)
        let r = rig(catalog: [small, voice])
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.hub.settings.voiceModeTarget = "voice-en"
        #expect(r.hub.voiceModeOffer(memory: gb8)?.id == "whisper-small", "a voice (text to speech) is not a Voice Mode model")
        r.hub.settings.voiceModeTarget = "gone"
        #expect(r.hub.voiceModeOffer(memory: gb8)?.id == "whisper-small")
        #expect(r.hub.voiceDownload == .idle)
    }

    @Test func aDownloadFromSettingsLeavesTheVoiceModeChoiceAlone() async throws {
        let r = rig(catalog: [small, tiny])
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.hub.settings.voiceModeTarget = "whisper-small"
        await r.hub.downloader.start(tiny)?.value
        #expect(r.hub.settings.voiceModeTarget == "whisper-small")
        #expect(r.hub.settings.selectedSTT == nil, "Get in Settings does not select")
    }

    @Test func aBrokenCatalogShowsAsAnEmptyList() {
        let hub = VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            catalog: { throw VoiceCatalogError.missingBundle })
        #expect(hub.catalog.isEmpty)
        #expect(hub.models(.stt).count == 1)
    }

    @Test func settingsRoundTripThroughDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = VoiceSettings(defaults: defaults)
        #expect(settings.selectedSTT == nil && settings.selectedTTS == nil && !settings.readRepliesAloud)
        #expect(settings.forcedLanguage == nil && settings.lastLanguage == nil)
        settings.selectedSTT = "whisper-small"
        settings.selectedTTS = "voice-en"
        settings.readRepliesAloud = true
        settings.forcedLanguage = .vietnamese
        settings.lastLanguage = .english
        let again = VoiceSettings(defaults: defaults)
        #expect(again.selectedSTT == "whisper-small" && again.selectedTTS == "voice-en" && again.readRepliesAloud)
        #expect(again.forcedLanguage == .vietnamese && again.lastLanguage == .english)
        again.forcedLanguage = nil
        #expect(VoiceSettings(defaults: defaults).forcedLanguage == nil)
    }
}
