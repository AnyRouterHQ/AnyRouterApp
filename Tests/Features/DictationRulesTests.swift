import Testing
@testable import AnyRouter

struct DictationRulesTests {
    @Test func theTranscriptFollowsWhatWasAlreadyInTheField() {
        #expect(DictationRules.merge(base: "", transcript: "hello there") == "hello there")
        #expect(DictationRules.merge(base: "Note:", transcript: "hello there") == "Note: hello there")
        #expect(DictationRules.merge(base: "Note:\n", transcript: "hello there") == "Note:\nhello there")
        #expect(DictationRules.merge(base: "Note:", transcript: "  \n") == "Note:")
    }

    @Test func theFirstUseExplainsBeforeTheSystemAsks() {
        #expect(DictationRules.needsExplanation(microphone: .notDetermined, speechRecognition: .notDetermined))
        #expect(DictationRules.needsExplanation(microphone: .granted, speechRecognition: .notDetermined))
        #expect(DictationRules.needsExplanation(microphone: .notDetermined, speechRecognition: .granted))
        #expect(!DictationRules.needsExplanation(microphone: .granted, speechRecognition: .granted))
        #expect(!DictationRules.needsExplanation(microphone: .denied, speechRecognition: .granted))
    }

    @Test func theBadgeMenuListsEnglishVietnameseThenTheDeviceLanguagesOnce() {
        #expect(DictationRules.languageMenu(deviceLanguages: ["vi-VN", "fr-FR", "en-GB"]) == [.english, .vietnamese, VoiceLanguage("fr")])
        #expect(DictationRules.languageMenu(deviceLanguages: []) == [.english, .vietnamese])
    }

    @Test func theBadgeShowsTheForcedLanguageThenTheDetectedOneThenAuto() {
        #expect(DictationRules.badgeTitle(forced: .vietnamese, detected: .english) == "VI")
        #expect(DictationRules.badgeTitle(forced: nil, detected: .english) == "EN")
        #expect(DictationRules.badgeTitle(forced: nil, detected: nil) == "Auto")
    }

    @Test func eachPhaseHasItsOwnWords() {
        let phases: [DictationPhase] = [.preparing, .listening, .finishing]
        #expect(Set(phases.map(DictationRules.statusText)).count == 3)
        #expect(DictationRules.statusText(.idle).isEmpty)
    }

    @Test func silenceAfterSpeechEndsDictation() {
        var detector = SilenceDetector()
        let quiet1 = detector.observe(level: 0.6, at: 0)
        #expect(!quiet1)
        let quiet2 = detector.observe(level: 0.05, at: 1)
        #expect(!quiet2)
        let quiet3 = detector.observe(level: 0.05, at: 3.4)
        #expect(!quiet3)
        let quiet4 = detector.observe(level: 0.05, at: 3.6)
        #expect(quiet4)
    }

    @Test func speakingAgainRestartsTheQuietTimer() {
        var detector = SilenceDetector()
        _ = detector.observe(level: 0.6, at: 0)
        _ = detector.observe(level: 0.05, at: 1)
        let quiet5 = detector.observe(level: 0.6, at: 3)
        #expect(!quiet5)
        let quiet6 = detector.observe(level: 0.05, at: 4)
        #expect(!quiet6)
        let quiet7 = detector.observe(level: 0.05, at: 6)
        #expect(!quiet7)
        let quiet8 = detector.observe(level: 0.05, at: 6.5)
        #expect(quiet8)
    }

    @Test func nobodySpeakingEndsItAfterTheLongerWait() {
        var detector = SilenceDetector()
        let quiet9 = detector.observe(level: 0.01, at: 100)
        #expect(!quiet9)
        let quiet10 = detector.observe(level: 0.01, at: 107.9)
        #expect(!quiet10)
        let quiet11 = detector.observe(level: 0.01, at: 108)
        #expect(quiet11)
    }
}
