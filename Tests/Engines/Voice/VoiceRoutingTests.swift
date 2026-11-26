import Testing
@testable import AnyRouter

struct VoiceRoutingTests {
    private let whisper = VoiceFixtures.model("whisper-small", detects: true, weak: [])
    private let tiny = VoiceFixtures.model("whisper-tiny", detects: true, weak: ["vi"])
    private let voice = VoiceFixtures.model("voice-en", kind: .tts, languages: ["en", "fr"])

    private func choose(
        _ kind: VoiceModelKind = .stt, language: VoiceLanguage?, selected: String?, installed: Set<String>
    ) -> VoiceChoice {
        VoiceRouting.choose(kind: kind, language: language, selectedID: selected, installed: installed, catalog: [whisper, tiny, voice])
    }

    @Test func noSelectionOrTheSystemRowUsesTheSystemEngine() {
        #expect(choose(language: .english, selected: nil, installed: ["whisper-small"]) == .system(nil))
        #expect(choose(language: .english, selected: VoiceModel.systemID, installed: ["whisper-small"]) == .system(nil))
        #expect(choose(language: .english, selected: "gone-from-catalog", installed: ["gone-from-catalog"]) == .system(nil))
    }

    @Test func aSelectedModelThatIsNotDownloadedFallsBack() {
        #expect(choose(language: .english, selected: "whisper-small", installed: []) == .system(.notInstalled))
    }

    @Test func aSelectedAndInstalledModelIsUsedForALanguageItCovers() {
        #expect(choose(language: .vietnamese, selected: "whisper-small", installed: ["whisper-small"]) == .model(whisper))
    }

    @Test func aModelHandsOverALanguageItDoesNotListOrHandlesBadly() {
        let thai = VoiceLanguage("th")
        #expect(choose(.tts, language: thai, selected: "voice-en", installed: ["voice-en"]) == .system(.languageNotCovered(thai)))
        #expect(choose(.tts, language: .english, selected: "voice-en", installed: ["voice-en"]) == .model(voice))
        #expect(choose(language: .vietnamese, selected: "whisper-tiny", installed: ["whisper-tiny"]) == .system(.weakForLanguage(.vietnamese)))
        #expect(choose(language: .english, selected: "whisper-tiny", installed: ["whisper-tiny"]) == .model(tiny))
    }

    @Test func dictationWithNoLanguageYetNeedsAModelThatDetectsIt() {
        #expect(choose(language: nil, selected: "whisper-small", installed: ["whisper-small"]) == .model(whisper))
        var quiet = whisper
        quiet.detectsLanguage = false
        let choice = VoiceRouting.choose(
            kind: .stt, language: nil, selectedID: quiet.id, installed: [quiet.id], catalog: [quiet])
        #expect(choice == .system(.cannotDetectLanguage))
    }

    @Test func aSelectionOfTheOtherKindIsIgnored() {
        #expect(choose(.tts, language: .english, selected: "whisper-small", installed: ["whisper-small"]) == .system(nil))
    }

    @Test func theSettingsLineListsWhatGoesToTheSystem() {
        let handed = VoiceRouting.handedToSystem(voice, wanted: [.english, .vietnamese])
        #expect(handed == [.vietnamese])
        #expect(VoiceRouting.handedToSystem(tiny, wanted: [.english, .vietnamese]) == [.vietnamese])
    }

    @Test func candidatesKeepTheLastLanguageThenTheDeviceThenEnglish() {
        #expect(VoiceRouting.candidates(lastUsed: .vietnamese, deviceLanguages: ["en-US", "vi-VN"]) == [.vietnamese, .english])
        #expect(VoiceRouting.candidates(lastUsed: nil, deviceLanguages: ["vi-VN"]) == [.vietnamese, .english])
        #expect(VoiceRouting.candidates(lastUsed: nil, deviceLanguages: ["fr-FR", "de-DE"], limit: 3)
            == [VoiceLanguage("fr"), VoiceLanguage("de"), .english])
        #expect(VoiceRouting.candidates(lastUsed: nil, deviceLanguages: ["en-GB"]) == [.english])
    }

    @Test func theTestSentenceIsInTheLanguageOrEnglish() {
        #expect(VoiceSamples.sentence(for: .vietnamese).contains("giọng"))
        #expect(VoiceSamples.sentence(for: VoiceLanguage("xx")) == VoiceSamples.sentence(for: .english))
        #expect(!VoiceSamples.sentence(for: .english).isEmpty)
    }
}
