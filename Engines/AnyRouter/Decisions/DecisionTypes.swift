import Foundation

/// A model that answers typed questions about a text (`POST /api/v1/decisions`). Not a chat model.
struct DecisionModel: Identifiable, Hashable, Codable, Sendable {
    /// Wire id, e.g. `anyrouter/decision`.
    var id: String
    var name: String
}

struct DecisionQuestion: Identifiable, Equatable, Codable, Sendable {
    enum Kind: Equatable, Codable, Sendable {
        case yesNo
        case choice(options: [String])
        /// Ordered levels, lowest first. The model answers with a number from 0 to `levels.count - 1`.
        case rubric(levels: [String])
    }

    /// Key in the request's `questions` map and in the response's `answers` map.
    var id: String
    var prompt: String
    var kind: Kind

    var wire: [String: Any] {
        switch kind {
        case .yesNo:
            return ["type": "noul", "instructions": prompt]
        case .choice(let options):
            var criteria: [String: Any] = [:]
            for option in options { criteria[option] = NSNull() }
            return ["type": "choice", "instructions": prompt, "criteria": criteria]
        case .rubric(let levels):
            return ["type": "score", "instructions": prompt, "criteria": levels]
        }
    }
}

struct DecisionRequest: Equatable, Codable, Sendable {
    var model: String
    var state: String
    var questions: [DecisionQuestion]

    func jsonBody() throws -> Data {
        var map: [String: Any] = [:]
        for question in questions { map[question.id] = question.wire }
        return try JSONSerialization.data(
            withJSONObject: ["model": model, "state": state, "questions": map], options: [.sortedKeys])
    }
}

struct DecisionAnswer: Identifiable, Equatable, Codable, Sendable {
    struct Option: Equatable, Codable, Sendable {
        var label: String
        var probability: Double
    }

    struct Verdict: Equatable, Codable, Sendable {
        /// "Yes", the picked option, or the score.
        var headline: String
        /// Probability of the headline, 0 to 1. Yes/no and choice.
        var probability: Double?
        var score: Double?
        /// Highest level of a rubric, so a gauge can show where the score sits.
        var maxScore: Double?
        /// The rubric level's description.
        var note: String?
        var confidence: Double?
        /// Every option with its probability, most likely first.
        var options: [Option]
    }

    enum Outcome: Equatable, Codable, Sendable {
        case answered(Verdict)
        case refused(String)
        case unreadable
    }

    var id: String
    var prompt: String
    var outcome: Outcome
    var citations: [String]
}

struct DecisionResult: Equatable, Codable, Sendable {
    var model: String
    /// In the order the questions were asked.
    var answers: [DecisionAnswer]
    var inputTokens: Int
    var outputTokens: Int
    /// USD charged. 0 for free models.
    var cost: Double?
    /// The model declined the whole request.
    var refusal: String?
    /// Seconds, measured by the client.
    var latency: Double

    static func parse(_ data: Data, for request: DecisionRequest) throws -> DecisionResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AnyRouterError.badResponse
        }
        let refusal = Self.text(root["refusal"])
        let rawAnswers = root["answers"] as? [String: Any]
        guard rawAnswers != nil || refusal != nil else { throw AnyRouterError.badResponse }
        let usage = root["usage"] as? [String: Any]
        let answers = request.questions.map { question -> DecisionAnswer in
            guard let raw = rawAnswers?[question.id] as? [String: Any] else {
                return DecisionAnswer(
                    id: question.id, prompt: question.prompt,
                    outcome: refusal.map(DecisionAnswer.Outcome.refused) ?? .unreadable, citations: [])
            }
            return DecisionAnswer(
                id: question.id, prompt: question.prompt,
                outcome: outcome(raw, question: question), citations: citations(raw["citations"]))
        }
        return DecisionResult(
            model: (root["model"] as? String) ?? request.model,
            answers: answers,
            inputTokens: (usage?["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage?["output_tokens"] as? Int) ?? 0,
            cost: usage?["cost"] as? Double,
            refusal: refusal,
            latency: 0)
    }

    // MARK: Answer reading

    private static func outcome(_ raw: [String: Any], question: DecisionQuestion) -> DecisionAnswer.Outcome {
        if let refusal = text(raw["refusal"]) { return .refused(refusal) }
        let type = (raw["type"] as? String)?.lowercased()
        let verdict: DecisionAnswer.Verdict?
        switch type {
        case "noul": verdict = yesNo(raw)
        case "choice": verdict = choice(raw)
        case "score": verdict = score(raw, question: question)
        default: verdict = nil
        }
        return verdict.map(DecisionAnswer.Outcome.answered) ?? .unreadable
    }

    private static func yesNo(_ raw: [String: Any]) -> DecisionAnswer.Verdict? {
        guard let value = number(raw["noul"]) else { return nil }
        let yes = clamp(value)
        // Exactly 0.5 reads as Yes: the API documents noul as the probability of true.
        let isYes = yes >= 0.5
        return .init(
            headline: isYes ? "Yes" : "No", probability: isYes ? yes : 1 - yes,
            confidence: nil,
            options: [.init(label: "Yes", probability: yes), .init(label: "No", probability: 1 - yes)])
    }

    private static func choice(_ raw: [String: Any]) -> DecisionAnswer.Verdict? {
        var probabilities: [String: Double] = [:]
        for (key, value) in (raw["probabilities"] as? [String: Any]) ?? [:] {
            if let number = number(value) { probabilities[key] = clamp(number) }
        }
        let ranked = probabilities.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let picked = (raw["choice"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? ranked.first?.key else {
            return nil
        }
        return .init(
            headline: picked, probability: probabilities[picked], confidence: confidence(raw),
            options: ranked.map { .init(label: $0.key, probability: $0.value) })
    }

    private static func score(_ raw: [String: Any], question: DecisionQuestion) -> DecisionAnswer.Verdict? {
        // A score is a level number. Anything else (and anything huge) is not a usable answer.
        guard let score = number(raw["score"]), (0...1000).contains(score) else { return nil }
        let legend = raw["legend"] as? [String: Any] ?? [:]
        var levels: [String] = []
        if case .rubric(let given) = question.kind { levels = given }
        func label(_ level: Int) -> String? {
            text(legend[String(level)]) ?? (levels.indices.contains(level) ? levels[level] : nil)
        }
        var probabilities: [(level: Int, value: Double)] = []
        for (key, value) in (raw["probabilities"] as? [String: Any]) ?? [:] {
            if let level = Int(key), let number = number(value) { probabilities.append((level, clamp(number))) }
        }
        probabilities.sort { $0.level < $1.level }
        let top = max(levels.count - 1, probabilities.last?.level ?? 0, Int(score.rounded(.up)), 1)
        let lower = Int(score.rounded(.down))
        let upper = Int(score.rounded(.up))
        let note: String? = lower == upper
            ? label(lower)
            : [label(lower), label(upper)].compactMap { $0 }.joined(separator: " to ").nilIfEmpty
        return .init(
            headline: format(score), probability: nil, score: score, maxScore: Double(top), note: note,
            confidence: confidence(raw),
            options: probabilities.map { .init(label: label($0.level) ?? "Level \($0.level)", probability: $0.value) })
    }

    private static func citations(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            if let string = text(item) { return string }
            guard let object = item as? [String: Any] else { return nil }
            return text(object["url"]) ?? text(object["title"])
        }
    }

    // MARK: Small readers

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue.isFinite ? number.doubleValue : nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func confidence(_ raw: [String: Any]) -> Double? {
        guard let value = number(raw["confidence"]), (0...1).contains(value) else { return nil }
        return value
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func format(_ score: Double) -> String {
        score == score.rounded() ? String(Int(score)) : String(format: "%.2f", score).replacingOccurrences(
            of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
