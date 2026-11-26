import Foundation
import Testing
@testable import AnyRouter

struct TTSKitRulesTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    @Test func theLanguagesAreTheOnesQwen3TTSListsAndNotVietnamese() {
        // The names are Qwen3Language in argmax-oss-swift 1.1.1; the backend hands them to TTSKit as they are.
        #expect(TTSKitLanguage.allCases.map(\.rawValue)
            == ["english", "chinese", "japanese", "korean", "german", "french", "russian", "portuguese", "spanish", "italian"])
        #expect(TTSKitLanguage(.vietnamese) == nil)
        #expect(TTSKitLanguage(VoiceLanguage("th")) == nil)
    }

    @Test func aLanguageMapsByItsPrimaryTag() {
        for language in TTSKitLanguage.allCases {
            #expect(TTSKitLanguage(VoiceLanguage(language.code)) == language)
        }
        #expect(TTSKitLanguage(VoiceLanguage("zh-Hans")) == .chinese)
        #expect(TTSKitLanguage(VoiceLanguage("pt_BR")) == .portuguese)
        #expect(TTSKitLanguage(VoiceLanguage("EN-gb")) == .english)
    }

    @Test func eachLanguageHasASpeakerTheModelKnows() {
        let known: Set<String> = ["ryan", "aiden", "ono-anna", "sohee", "eric", "dylan", "serena", "vivian", "uncle-fu"]
        for language in TTSKitLanguage.allCases { #expect(known.contains(language.speaker), "\(language)") }
        #expect(TTSKitLanguage.japanese.speaker == "ono-anna")
        #expect(TTSKitLanguage.korean.speaker == "sohee")
        #expect(TTSKitLanguage.chinese.speaker == "vivian")
        #expect(TTSKitLanguage.german.speaker == "ryan")
    }

    @Test func failuresBecomeMessagesTheReaderCanActOn() {
        #expect(TTSFailure.map(TTSFailure.modelUnavailable).errorDescription?.contains("download it again") == true)
        #expect(TTSFailure.map(TTSFailure.audioFailed("no output")).errorDescription?.contains("no output") == true)
        #expect(TTSFailure.map(TTSFailure.failed("odd")).errorDescription?.contains("odd") == true)
        #expect(TTSFailure.map(Boom()).errorDescription?.contains("boom") == true)
        #expect(TTSFailure.map(VoiceError.microphoneDenied) == .microphoneDenied)
    }
}
