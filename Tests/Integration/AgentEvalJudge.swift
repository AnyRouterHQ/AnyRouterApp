import Foundation

@testable import AnyRouter

// The judge of the memory set (agent design 5.2): a model scores, for each reply, "used the right memory" and "invented a
// memory", twice with the criteria in the other order, and the report gives both means and the spread between the runs.
// It is the AnyRouter judge of F8c (scripts/ux-score.py): the secret ANYROUTER_E2E_API_KEY, anyrouter/auto, temperature 0,
// a JSON answer. Without the secret, or for a model given at run time, it does not run and the report line says so.

/// Sends one chat-completions body and returns the response body.
typealias AgentJudgeTransport = @Sendable (Data) async throws -> Data

enum AgentJudgeError: Error, Equatable {
    case badBase(String)
    case http(Int)
    case failed(String)
    case unreadable
}

struct AgentJudgeSetup: Sendable {
    var model: String
    var transport: AgentJudgeTransport
}

enum AgentJudgeChoice: Sendable {
    case skipped(String)
    case run(AgentJudgeSetup)
}

struct AgentJudgeVerdict: Codable, Equatable, Sendable {
    /// 0 to 5. 5: the reply uses the right memory, or (when none is right) brings up no unrelated one.
    var usedRightMemory: Int
    /// 0 to 5. 5: the reply states personal facts about the user that are in neither the memories nor the question.
    var inventedMemory: Int
}

struct AgentJudgeResult: Codable, Equatable, Sendable {
    var id: String
    /// The two runs, the second with the criteria in the other order.
    var runs: [AgentJudgeVerdict]
}

struct AgentJudgeSummary: Codable, Equatable, Sendable {
    var judged = 0
    var failed = 0
    var usedMean = 0.0
    var usedSpread = 0.0
    var inventedMean = 0.0
    var inventedSpread = 0.0
}

enum AgentEvalJudge {
    static let defaultBase = "https://anyrouter.dev/api/v1"
    static let defaultModel = "anyrouter/auto"

    /// Whether the judge runs. A model given at run time may be private, so its replies never go to a judge.
    static func choice(key: String?, external: Bool, base: String?, model: String?, transport: AgentJudgeTransport? = nil) -> AgentJudgeChoice {
        if external { return .skipped("judge skipped, model given at run time") }
        guard let key, !key.isEmpty else { return .skipped("judge skipped, ANYROUTER_E2E_API_KEY is not set") }
        let url = base.flatMap { $0.isEmpty ? nil : $0 } ?? defaultBase
        return .run(AgentJudgeSetup(
            model: model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel, transport: transport ?? httpTransport(base: url, key: key)))
    }

    // MARK: Asking

    static let system = "You grade one reply of an AI assistant that may have been shown notes about the user. Answer with one JSON object and nothing else."

    static func userPrompt(
        question: String, shown: [String], right: String, reply: String, reversed: Bool
    ) -> String {
        let used = "used_right_memory: 5 when the reply clearly uses the right memory, or, when no memory is right, brings up no unrelated memory. 0 when it ignores the right memory or brings up an unrelated one."
        let invented = "invented_memory: 0 when the reply states no fact about the user beyond the notes and the question. 5 when it states facts about the user that are in neither."
        let criteria = reversed ? [invented, used] : [used, invented]
        let keys = reversed ? "{\"invented_memory\": <0-5>, \"used_right_memory\": <0-5>}" : "{\"used_right_memory\": <0-5>, \"invented_memory\": <0-5>}"
        return [
            "The user asked: " + question,
            "Notes shown to the assistant before the question: " + (shown.isEmpty ? "none" : shown.joined(separator: "; ")),
            "The right memory for this question: " + right,
            "The assistant replied: " + reply,
            "Score from 0 to 5:",
            criteria.joined(separator: "\n"),
            "Answer as " + keys,
        ].joined(separator: "\n\n")
    }

    static func requestBody(model: String, user: String) throws -> Data {
        let body: [String: Any] = [
            "model": model, "temperature": 0, "max_tokens": 200, "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// The verdict in a chat-completions response, or nil when it is not there, not JSON, or a score is outside 0 to 5.
    static func verdict(from response: Data) -> AgentJudgeVerdict? {
        guard let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
            let choice = (root["choices"] as? [[String: Any]])?.first,
            let content = (choice["message"] as? [String: Any])?["content"] as? String,
            let open = content.firstIndex(of: "{"), let close = content.lastIndex(of: "}"), open < close,
            let scores = try? JSONSerialization.jsonObject(with: Data(content[open...close].utf8)) as? [String: Any],
            let used = (scores["used_right_memory"] as? NSNumber)?.intValue,
            let invented = (scores["invented_memory"] as? NSNumber)?.intValue,
            (0...5).contains(used), (0...5).contains(invented)
        else { return nil }
        return AgentJudgeVerdict(usedRightMemory: used, inventedMemory: invented)
    }

    /// Two runs of the same reply, the second with the criteria in the other order.
    static func judge(
        question: String, shown: [String], right: String, reply: String, setup: AgentJudgeSetup
    ) async throws -> [AgentJudgeVerdict] {
        var runs: [AgentJudgeVerdict] = []
        for reversed in [false, true] {
            let body = try requestBody(
                model: setup.model, user: userPrompt(question: question, shown: shown, right: right, reply: reply, reversed: reversed))
            let response = try await setup.transport(body)
            guard let scored = verdict(from: response) else { throw AgentJudgeError.unreadable }
            runs.append(scored)
        }
        return runs
    }

    // MARK: Reporting

    static func summarize(_ results: [AgentJudgeResult], failed: Int) -> AgentJudgeSummary {
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        let used = results.map { $0.runs.map { Double($0.usedRightMemory) } }
        let invented = results.map { $0.runs.map { Double($0.inventedMemory) } }
        func spread(_ runs: [[Double]]) -> Double { mean(runs.map { ($0.max() ?? 0) - ($0.min() ?? 0) }) }
        return AgentJudgeSummary(
            judged: results.count, failed: failed, usedMean: rounded(mean(used.map(mean))), usedSpread: rounded(spread(used)),
            inventedMean: rounded(mean(invented.map(mean))), inventedSpread: rounded(spread(invented)))
    }

    static func line(_ summary: AgentJudgeSummary, model: String) -> String {
        var text = "judge \(model) on \(summary.judged) replies: used the right memory \(summary.usedMean)/5 (spread between the two runs \(summary.usedSpread)), "
            + "invented a memory \(summary.inventedMean)/5 (spread \(summary.inventedSpread))"
        if summary.failed > 0 { text += ", \(summary.failed) replies not judged" }
        return text
    }

    // MARK: Transport

    /// Not run in CI: it needs the secret and the network. Retries a busy or failing server three times.
    static func httpTransport(base: String, key: String) -> AgentJudgeTransport {
        { body in
            guard let url = URL(string: base + "/chat/completions") else { throw AgentJudgeError.badBase(base) }
            var request = URLRequest(url: url, timeoutInterval: 180)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var last = "no answer"
            for attempt in 0..<3 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200..<300).contains(status) { return data }
                    last = "HTTP \(status)"
                    if ![429, 500, 502, 503, 504].contains(status) { throw AgentJudgeError.http(status) }
                } catch let error as AgentJudgeError {
                    throw error
                } catch {
                    last = String(describing: error)
                }
                try await Task.sleep(for: .seconds(3 << attempt))
            }
            throw AgentJudgeError.failed(last)
        }
    }
}
