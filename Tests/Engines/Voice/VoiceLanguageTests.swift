import Foundation
import Testing
@testable import AnyRouter

struct VoiceLanguageTests {
    @Test func tagsReduceToTheirPrimaryLanguage() {
        #expect(VoiceLanguage("vi-VN").code == "vi")
        #expect(VoiceLanguage("zh_Hans_CN").code == "zh")
        #expect(VoiceLanguage("EN").code == "en")
        #expect(VoiceLanguage("").code == "")
        #expect(VoiceLanguage("en-US") == .english)
    }

    @Test func itRoundTripsAsAPlainString() throws {
        let data = try JSONEncoder().encode(["lang": VoiceLanguage("vi-VN")])
        #expect(String(decoding: data, as: UTF8.self) == "{\"lang\":\"vi\"}")
        #expect(try JSONDecoder().decode([String: VoiceLanguage].self, from: data)["lang"] == .vietnamese)
    }

    @Test func itLabelsItself() {
        #expect(VoiceLanguage.vietnamese.badge == "VI")
        #expect(!VoiceLanguage.vietnamese.name.isEmpty)
        #expect(VoiceLanguage.english < VoiceLanguage.vietnamese)
        #expect(VoiceLanguage.vietnamese.locale.identifier == "vi")
        #expect(!VoiceLanguage.device.code.isEmpty)
    }

    @Test func theTextRecognizerTellsVietnameseFromEnglish() {
        #expect(VoiceLanguageDetector.dominant("Xin chào, hôm nay bạn khỏe không?") == .vietnamese)
        #expect(VoiceLanguageDetector.dominant("The weather is nice today, so we walked to the park.") == .english)
        #expect(VoiceLanguageDetector.dominant("") == nil)
        #expect(VoiceLanguageDetector.hypotheses("The weather is nice today")[.english, default: 0] > 0.5)
    }
}
