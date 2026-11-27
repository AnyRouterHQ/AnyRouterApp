import Foundation

/// Recall before the send (agent design 2.4): facts and chat summaries scored against the user's question with BM25 over
/// words, the best three put in front of the question for that request only. No model call, so it runs on every engine.
/// A word that matches exactly counts in full; one that matches only without case and tone marks counts half, because
/// folding merges Vietnamese words that differ only by a tone mark.
enum MemoryRecallLogic {
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let text: String
    }

    struct Hit: Equatable, Sendable {
        let candidate: Candidate
        let score: Double
    }

    static let maxHits = 3
    static let heading = "Things the user told you before:"

    /// Words too common to say what a question is about, as typed: "an" is a stop word, "ăn" (eat) is not.
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "could", "do", "does", "for", "from", "have", "how",
        "i", "if", "in", "is", "it", "me", "my", "of", "on", "or", "please", "so", "that", "the", "this", "to", "was", "we",
        "what", "when", "where", "which", "who", "why", "will", "with", "would", "you", "your",
        "anh", "bạn", "các", "cho", "chị", "có", "của", "được", "em", "gì", "không", "là", "mình", "một", "nào", "này",
        "nhé", "những", "sao", "thì", "tôi", "và", "với", "toi", "la", "cua", "va", "co", "khong", "mot", "voi", "gi",
    ]

    /// The best items for the question, at most three, whole, within the budget.
    static func recall(_ question: String, from candidates: [Candidate], budget: Int) -> [Hit] {
        var hits: [Hit] = []
        var lines = [heading]
        for hit in rank(question, candidates) where hits.count < maxHits {
            let candidate = lines + ["- " + hit.candidate.text]
            guard TokenCountLogic.estimate(candidate.joined(separator: "\n")) <= budget else { continue }
            lines = candidate
            hits.append(hit)
        }
        return hits
    }

    /// Every candidate that shares a word with the question, best first. No score floor: BM25 gives a word that every item
    /// holds a tiny weight, so a floor would drop the only matches of a small memory. The live set (unit L1) checks traps.
    static func rank(_ question: String, _ candidates: [Candidate]) -> [Hit] {
        let terms = Array(Set(words(question).filter { !stopWords.contains($0) }.map(fold)))
        let documents = candidates.map { words($0.text) }
        let folded = documents.map { $0.map(fold) }
        let averageLength = Double(documents.map(\.count).reduce(0, +)) / Double(max(documents.count, 1))
        let count = Double(documents.count)
        let weights = terms.map { term in
            let containing = Double(folded.filter { $0.contains(term) }.count)
            return log(1 + (count - containing + 0.5) / (containing + 0.5))
        }
        let exact = Set(words(question))
        let scored = candidates.indices.map { index in
            Hit(candidate: candidates[index], score: score(
                terms: terms, weights: weights, exact: exact, words: documents[index], folded: folded[index], averageLength: averageLength))
        }
        return scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }
    }

    /// The footer's words: "Used 1 memory", "Used 3 memories".
    static func usedLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "Used 1 memory") : String(localized: "Used \(count) memories")
    }

    /// The recalled items as the text that goes in front of the question, for this request only. Nil without hits.
    static func block(_ hits: [Hit]) -> String? {
        hits.isEmpty ? nil : ([heading] + hits.map { "- " + $0.candidate.text }).joined(separator: "\n")
    }

    /// Lowercased words; letters and digits only.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// BM25 (k1 1.2, b 0.75) over folded terms. A word counts 1 when it is also one of the question's words as typed,
    /// 0.5 when it matches only after folding.
    private static func score(
        terms: [String], weights: [Double], exact: Set<String>, words: [String], folded: [String], averageLength: Double
    ) -> Double {
        let lengthNorm = 1.2 * (0.25 + 0.75 * Double(words.count) / max(averageLength, 1))
        return zip(terms, weights).reduce(0) { total, pair in
            let frequency = zip(words, folded).reduce(0.0) { sum, word in
                sum + (word.1 != pair.0 ? 0 : exact.contains(word.0) ? 1 : 0.5)
            }
            return total + pair.1 * frequency * 2.2 / (frequency + lengthNorm)
        }
    }
}
