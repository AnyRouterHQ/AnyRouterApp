import Foundation

/// Room for tool results inside one run on a small window (agent design 3.4): each new result is cut to what the window
/// has left, and when the next round would not fit, results older than the newest three become one-line stubs that keep
/// the address, so the model can fetch it again. Today the local loop uses it; the app loop (unit G3) takes it over.
enum RunBudgetLogic {
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
