import Testing
@testable import AnyRouter

struct WhisperRulesTests {
    private func seg(_ start: Float, _ end: Float, _ text: String) -> WhisperSegment {
        WhisperSegment(start: start, end: end, text: text)
    }

    // MARK: Transcript

    @Test func allButTheLastTwoPhrasesAreConfirmedSoTheNextPassStartsAfterThem() {
        var transcript = WhisperTranscript()
        transcript.apply([seg(0, 2, " one"), seg(2, 4, " two"), seg(4, 6, " three"), seg(6, 8, " four")])
        #expect(transcript.confirmed.map(\.text) == [" one", " two"])
        #expect(transcript.confirmedEnd == 4)
        #expect(transcript.text == "one two three four")
    }

    @Test func twoPhrasesOrFewerStayTentativeAndASecondPassReplacesThem() {
        var transcript = WhisperTranscript()
        transcript.apply([seg(0, 2, " helo"), seg(2, 4, " wurld")])
        #expect(transcript.confirmedEnd == 0)
        transcript.apply([seg(0, 2, " hello"), seg(2, 4, " world")])
        #expect(transcript.text == "hello world")
    }

    @Test func aLaterPassNeverRepeatsOrRewindsWhatIsConfirmed() {
        var transcript = WhisperTranscript()
        transcript.apply([seg(0, 2, "a"), seg(2, 4, "b"), seg(4, 6, "c")])
        #expect(transcript.confirmedEnd == 2)
        // A pass that overlaps the confirmed phrase must not add it twice.
        transcript.apply([seg(0, 2, "a"), seg(2, 4, "b"), seg(4, 6, "c"), seg(6, 8, "d"), seg(8, 10, "e")])
        #expect(transcript.confirmed.map(\.text) == ["a", "b", "c"])
        #expect(transcript.text == "a b c d e")
    }

    @Test func finishingConfirmsEveryPhrase() {
        var transcript = WhisperTranscript()
        transcript.apply([seg(0, 2, "one"), seg(2, 4, "two")], isFinal: true)
        #expect(transcript.confirmed.count == 2)
        #expect(transcript.confirmedEnd == 4)

        var other = WhisperTranscript()
        other.apply([seg(0, 2, "x"), seg(2, 4, "y")])
        other.finish()
        #expect(other.confirmed.map(\.text) == ["x", "y"])
        #expect(other.text == "x y")
    }

    @Test func specialTokensAndEmptyPhrasesAreNotWords() {
        var transcript = WhisperTranscript()
        transcript.apply([seg(0, 1, "<|startoftranscript|><|vi|> Xin chào<|endoftext|>"), seg(1, 2, "  <|nospeech|> ")], isFinal: true)
        #expect(transcript.text == "Xin chào")
    }

    // MARK: Language

    @Test func detectionWaitsForEnoughSpeechAndHappensOnce() {
        var trigger = WhisperLanguageTrigger(forced: nil)
        #expect(!trigger.shouldDetect(voicedSeconds: 1.0))
        #expect(trigger.shouldDetect(voicedSeconds: 1.6))
        trigger.settle(.vietnamese)
        #expect(!trigger.shouldDetect(voicedSeconds: 30))
        trigger.settle(.english)
        #expect(trigger.language == .vietnamese)
    }

    @Test func aLanguageTheUserChoseSkipsDetection() {
        let trigger = WhisperLanguageTrigger(forced: .english)
        #expect(trigger.language == .english)
        #expect(!trigger.shouldDetect(voicedSeconds: 30, isEnding: true))
    }

    @Test func aShortDictationThatEndsStillGetsAGuess() {
        let trigger = WhisperLanguageTrigger(forced: nil)
        #expect(!trigger.shouldDetect(voicedSeconds: 0.5))
        #expect(trigger.shouldDetect(voicedSeconds: 0.5, isEnding: true))
        #expect(!trigger.shouldDetect(voicedSeconds: 0.1, isEnding: true))
    }

    @Test func whisperCodesMapToOurLanguages() {
        #expect(WhisperLanguages.voiceLanguage(fromWhisper: "vi") == .vietnamese)
        #expect(WhisperLanguages.voiceLanguage(fromWhisper: "jw") == VoiceLanguage("jv"))
        #expect(WhisperLanguages.whisperCode(for: VoiceLanguage("jv")) == "jw")
        #expect(WhisperLanguages.whisperCode(for: .english) == "en")
    }

    // MARK: Audio

    @Test func voicedSecondsCountsOnlyLoudBuffers() {
        let energy: [Float] = [0.0, 0.9, 0.8, 0.1]
        #expect(WhisperVoice.voicedSeconds(energy: energy, sampleCount: 64_000) == 2)
        #expect(WhisperVoice.voicedSeconds(energy: [], sampleCount: 64_000) == 0)
        #expect(WhisperVoice.voicedSeconds(energy: [0.1, 0.2], sampleCount: 64_000) == 0)
    }

    @Test func aPassNeedsMoreThanASecondOfNewAudioWithSpeechInIt() {
        let loud = [Float](repeating: 0.9, count: 20)
        let quiet = [Float](repeating: 0.0, count: 20)
        #expect(!WhisperPacing.shouldTranscribe(energy: loud, sampleCount: 24_000, transcribedSamples: 16_000))
        #expect(WhisperPacing.shouldTranscribe(energy: loud, sampleCount: 48_000, transcribedSamples: 16_000))
        #expect(!WhisperPacing.shouldTranscribe(energy: quiet, sampleCount: 48_000, transcribedSamples: 16_000))
        // Speech earlier in the recording does not count for the new part.
        let spokeThenSilence = [Float](repeating: 0.9, count: 5) + [Float](repeating: 0.0, count: 15)
        #expect(!WhisperPacing.shouldTranscribe(energy: spokeThenSilence, sampleCount: 48_000, transcribedSamples: 16_000))
    }

    // MARK: Errors

    @Test func failuresBecomeMessagesTheUserCanActOn() {
        #expect(WhisperFailure.map(VoiceError.microphoneDenied) == .microphoneDenied)
        let model = WhisperFailure.map(WhisperFailure.modelUnavailable)
        #expect(model.errorDescription?.contains("Delete it in Settings") == true)
        let other = WhisperFailure.map(WhisperFailure.failed("decoder"))
        #expect(other.errorDescription == "Speech recognition stopped: decoder")
        #expect(WhisperFailure.map(WhisperFailure.microphoneUnavailable) == .audioFailed("The microphone could not start."))
    }
}
