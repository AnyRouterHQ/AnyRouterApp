import Testing
@testable import AnyRouter

struct LanguageArbiterTests {
    private static let agree: @Sendable (String) -> [VoiceLanguage: Double] = { text in
        if text.contains("xin") { return [.vietnamese: 0.9, .english: 0.05] }
        if text.contains("hello") { return [.english: 0.9] }
        return [.english: 0.4, .vietnamese: 0.3]
    }

    private func reading(_ language: VoiceLanguage, _ text: String, confidence: Double? = nil, final: Bool = false) -> LanguageReading {
        LanguageReading(language: language, text: text, confidence: confidence, isFinal: final)
    }

    @Test func vietnameseSpeechBeatsTheEnglishTranscriberPrintingGuesses() {
        var arbiter = LanguageArbiter(candidates: [.english, .vietnamese], agreement: Self.agree)
        arbiter.record(reading(.english, "sin chow ban oi hom nay"))
        arbiter.record(reading(.vietnamese, "xin chào bạn hôm nay"))
        #expect(arbiter.verdict(force: false) == .vietnamese)
    }

    @Test func englishSpeechIsRecognizedToo() {
        var arbiter = LanguageArbiter(candidates: [.vietnamese, .english], agreement: Self.agree)
        arbiter.record(reading(.vietnamese, "hê lô then my friend"))
        arbiter.record(reading(.english, "hello there my friend"))
        #expect(arbiter.verdict(force: false) == .english)
    }

    @Test func tooLittleTextGivesNoVerdict() {
        var arbiter = LanguageArbiter(candidates: [.english, .vietnamese], agreement: Self.agree)
        arbiter.record(reading(.english, "hello"))
        arbiter.record(reading(.vietnamese, "xin"))
        #expect(arbiter.leader == nil)
        #expect(arbiter.verdict(force: true) == nil)
    }

    @Test func aTieWaitsUntilForcedThenTakesTheFirstCandidate() {
        let even: @Sendable (String) -> [VoiceLanguage: Double] = { _ in [.english: 0.5, .vietnamese: 0.5] }
        var arbiter = LanguageArbiter(candidates: [.english, .vietnamese], agreement: even)
        arbiter.record(reading(.english, "some words that mean little"))
        arbiter.record(reading(.vietnamese, "some words that mean little"))
        #expect(arbiter.verdict(force: false) == nil)
        #expect(arbiter.verdict(force: true) == .english)
    }

    @Test func confidenceBreaksALanguageTieOnFinalResults() {
        let both: @Sendable (String) -> [VoiceLanguage: Double] = { _ in [.english: 0.8, .vietnamese: 0.8] }
        var arbiter = LanguageArbiter(candidates: [.english, .vietnamese], agreement: both)
        arbiter.record(reading(.english, "some words that mean little", confidence: 0.5, final: true))
        arbiter.record(reading(.vietnamese, "some words that mean little", confidence: 0.9, final: true))
        #expect(arbiter.verdict(force: false) == .vietnamese)
    }

    @Test func oneCandidateNeedsNoMargin() {
        var arbiter = LanguageArbiter(candidates: [.vietnamese], agreement: Self.agree)
        arbiter.record(reading(.vietnamese, "xin chào bạn hôm nay"))
        #expect(arbiter.verdict(force: false) == .vietnamese)
    }

    @Test func readingsInOtherLanguagesAreIgnored() {
        var arbiter = LanguageArbiter(candidates: [.english], agreement: Self.agree)
        arbiter.record(reading(.vietnamese, "xin chào bạn hôm nay"))
        #expect(arbiter.leader == nil)
    }

    @Test func theDefaultRecognizerTellsVietnameseFromEnglish() {
        var arbiter = LanguageArbiter(candidates: [.english, .vietnamese])
        arbiter.record(reading(.english, "xin chao ban hom nay troi dep qua"))
        arbiter.record(reading(.vietnamese, "Xin chào bạn, hôm nay trời đẹp quá"))
        #expect(arbiter.verdict(force: true) == .vietnamese)
    }
}
