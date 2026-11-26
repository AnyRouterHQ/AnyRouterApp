import Foundation

/// One transcriber's view of the audio so far, in the language it was told to expect.
struct LanguageReading: Equatable, Sendable {
    var language: VoiceLanguage
    var text: String
    /// Mean recognizer confidence, 0 to 1. Only final results carry it.
    var confidence: Double?
    var isFinal: Bool
}

/// Picks the language of speech when the recognizer cannot say. Several transcribers, one per candidate language, listen
/// to the same audio. A transcriber that expects the wrong language still prints words, so the arbiter asks two questions:
/// does a text-language recognizer agree the text is in that language, and how sure was the transcriber.
/// It is a heuristic; `DictationRules` and the Settings page say that Whisper detects from the audio itself.
struct LanguageArbiter: Sendable {
    /// Text shorter than this is too little to judge.
    static let minimumCharacters = 12
    /// The leader must beat the runner-up by this much, unless the caller forces a verdict.
    static let margin = 0.1

    let candidates: [VoiceLanguage]
    private let agreement: @Sendable (String) -> [VoiceLanguage: Double]
    private var readings: [VoiceLanguage: LanguageReading] = [:]

    init(candidates: [VoiceLanguage],
         agreement: @escaping @Sendable (String) -> [VoiceLanguage: Double] = { VoiceLanguageDetector.hypotheses($0) }) {
        self.candidates = candidates
        self.agreement = agreement
    }

    mutating func record(_ reading: LanguageReading) {
        guard candidates.contains(reading.language) else { return }
        readings[reading.language] = reading
    }

    func score(_ language: VoiceLanguage) -> Double {
        guard let reading = readings[language], reading.text.count >= Self.minimumCharacters else { return 0 }
        let text = agreement(reading.text)[language] ?? 0
        guard let confidence = reading.confidence else { return text }
        return 0.7 * text + 0.3 * confidence
    }

    /// The language with the best score so far, in candidate order on a tie. Nil before any reading has enough text.
    var leader: VoiceLanguage? {
        let ranked = candidates.map { (language: $0, score: score($0)) }.filter { $0.score > 0 }
        return ranked.max { $0.score < $1.score }?.language
    }

    /// The verdict, once one candidate clearly leads. With `force`, the leader whatever the margin.
    func verdict(force: Bool) -> VoiceLanguage? {
        guard let leader else { return nil }
        if force || candidates.count == 1 { return leader }
        let others = candidates.filter { $0 != leader }.map(score)
        return score(leader) - (others.max() ?? 0) >= Self.margin ? leader : nil
    }
}
