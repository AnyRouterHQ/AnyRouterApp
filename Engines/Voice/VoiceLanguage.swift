import Foundation
import NaturalLanguage

/// A spoken language reduced to its primary subtag ("vi", "en", "zh"). Regions and scripts are the engine's business.
struct VoiceLanguage: Hashable, Sendable, Codable, Comparable {
    let code: String

    init(_ tag: String) {
        code = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? ""
    }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    static let english = VoiceLanguage("en")
    static let vietnamese = VoiceLanguage("vi")

    static func < (lhs: VoiceLanguage, rhs: VoiceLanguage) -> Bool { lhs.code < rhs.code }

    var locale: Locale { Locale(identifier: code) }

    /// "Vietnamese", in the language of the device.
    var name: String {
        guard let name = Locale.current.localizedString(forLanguageCode: code) else { return code }
        return name.localizedCapitalized
    }

    /// Two or three capitals for the small badge in the composer.
    var badge: String { code.uppercased() }

    /// The language of the device, from the first preferred language.
    static var device: VoiceLanguage { VoiceLanguage(Locale.preferredLanguages.first ?? "en") }
}

/// Which language a piece of text is written in, for choosing a voice per sentence.
enum VoiceLanguageDetector {
    /// Probability per language, strongest first in the caller's eyes. Empty for text with no letters.
    static func hypotheses(_ text: String, limit: Int = 4) -> [VoiceLanguage: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        var result: [VoiceLanguage: Double] = [:]
        for (language, probability) in recognizer.languageHypotheses(withMaximum: limit) {
            result[VoiceLanguage(language.rawValue), default: 0] += probability
        }
        return result
    }

    /// The language when the recognizer is sure enough, else nil. Short text is often a guess; the caller keeps the language of the previous sentence.
    static func dominant(_ text: String, minimumConfidence: Double = 0.6) -> VoiceLanguage? {
        hypotheses(text, limit: 1).first { $0.value >= minimumConfidence }?.key
    }
}
