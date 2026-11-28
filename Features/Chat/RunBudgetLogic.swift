import Foundation

/// Room for tool results inside one run on a small window (agent design 3.4): each new result is cut to what the window
/// has left, and when the next round would not fit, results older than the newest three become one-line stubs that keep
/// the address, so the model can fetch it again. A cloud run only clears, in large steps.
enum RunBudgetLogic {
    /// The room one run has for its rounds: the window less the answer's reserve.
    struct Budget: Equatable, Sendable {
        let window: Int
        /// A device model also cuts each new result to what is left; a cloud model only clears old results.
        let onDevice: Bool

        var limit: Int { window - RunBudgetLogic.reserve(window: window) }
    }

    /// The fewest tokens one cloud clearing frees: each clearing breaks the provider's prompt cache from that point.
    static let cloudClearingStep = 8_000

    /// One tool answer as the run keeps it.
    struct Result: Equatable, Sendable {
        let name: String
        let argumentsJSON: String
        let text: String
    }

    /// Results never cleared: the newest few are what the model is working with.
    static let keptResults = 3

    /// Tokens kept free for the answer (agent design 3.3).
    static func reserve(window: Int) -> Int { window > 4096 ? 1024 : 700 }

    /// One new result may take the smaller of a fixed cap and a third of what is left.
    static func resultCap(window: Int, left: Int) -> Int {
        min(window > 4096 ? 800 : 400, max(left, 0) / 3)
    }

    /// `text` cut to at most `tokens` tokens by the honest counter, with a note when it was cut.
    static func clip(_ text: String, tokens: Int) -> String {
        guard TokenCountLogic.estimate(text) > tokens else { return text }
        let note = "\n[Cut to fit the model's window.]"
        var low = 0
        var high = text.count
        while low < high {
            let middle = (low + high + 1) / 2
            if TokenCountLogic.estimate(String(text.prefix(middle)) + note) <= tokens { low = middle } else { high = middle - 1 }
        }
        return String(text.prefix(low)) + note
    }

    /// The line that stands for a cleared result: what was called, on what, and how long the answer was.
    static func stub(_ result: Result) -> String {
        let arguments = JSONValue.parse(result.argumentsJSON)
        let target = arguments?["url"]?.string ?? arguments?["query"]?.string
        return "[Result cleared: \(result.name)\(target.map { " " + $0 } ?? ""), \(result.text.count) characters]"
    }

    /// The rounds with their oldest `count` results stubbed, never one of the newest `keptResults`.
    static func stubbing(_ rounds: [[Result]], oldest count: Int) -> [[Result]] {
        var rounds = rounds
        let positions = rounds.indices.flatMap { round in rounds[round].indices.map { (round, $0) } }
        for (round, index) in positions.dropLast(keptResults).prefix(count) {
            let old = rounds[round][index]
            rounds[round][index] = Result(name: old.name, argumentsJSON: old.argumentsJSON, text: stub(old))
        }
        return rounds
    }

    /// How many of the oldest results a cloud run stubs, when `sent` were stubbed in its last request. None more while
    /// the rounds fit `limit`; else more, one at a time, until they fit and at least `cloudClearingStep` tokens are freed.
    /// When stubbing all but the newest `keptResults` cannot free that much, none more.
    static func cloudStubs(_ rounds: [[Result]], sent: Int, limit: Int, tokens: ([[Result]]) -> Int) -> Int {
        let before = tokens(stubbing(rounds, oldest: sent))
        guard before > limit else { return sent }
        let most = max(rounds.joined().count - keptResults, sent)
        var count = sent
        while count < most {
            count += 1
            let after = tokens(stubbing(rounds, oldest: count))
            if after <= limit, before - after >= cloudClearingStep { return count }
        }
        return before - tokens(stubbing(rounds, oldest: most)) >= cloudClearingStep ? most : sent
    }

    /// The rounds with the oldest results stubbed, one at a time, until `fits` says yes or only the newest
    /// `keptResults` are left whole.
    static func cleared(_ rounds: [[Result]], fits: ([[Result]]) -> Bool) -> [[Result]] {
        var rounds = rounds
        let positions = rounds.indices.flatMap { round in rounds[round].indices.map { (round, $0) } }
        for (round, index) in positions.dropLast(keptResults) where !fits(rounds) {
            let old = rounds[round][index]
            rounds[round][index] = Result(name: old.name, argumentsJSON: old.argumentsJSON, text: stub(old))
        }
        return rounds
    }
}
