import Foundation

/// Asks a model what the user's message says about the user. The only real one is Apple's on-device model
/// (AppleMemoryExtractor); tests use a fake.
protocol MemoryExtracting: Sendable {
    /// At most three short statements the user made about themselves in `message`. Empty when there are none, or when the
    /// model is not ready or fails: saving memories never stops or slows a reply.
    func statements(in message: String) async -> [String]
}

/// Extraction after a reply on Apple (agent design 2.3, unit M6): the looser classifier that decides whether to ask, the
/// request, and the checks on what comes back. Never on GGUF or MLX: a second generation would hold the one loaded model.
enum MemoryExtractionLogic {
    static let maxStatements = 3
    /// A longer message is a pasted text or a task, not a person talking about themselves.
    static let maxMessageLength = 600
    /// Words that make a sentence first person, as typed ("I'm" and "I've" split into "i" and the rest).
    private static let firstPersonWords: Set<String> = ["i", "my", "mine", "myself", "tôi", "mình", "tui"]

    static let instructions = """
        You find lasting facts a user states about themselves: who they are, where they live, family, work, tastes, \
        allergies, habits and preferences. Write each as the user would say it, in the user's language, short, in the \
        first person ("I'm vegetarian"). Never invent anything. Skip questions, tasks, one-time plans and anything about \
        other people's data. Return an empty list when the message states nothing lasting.
        """

    static func prompt(for message: String) -> String {
        "Message:\n" + message
    }

    /// Looser than RememberLogic: a first-person word in a sentence that is not a question, in a message of ordinary length.
    /// "Do you remember that film?" and "Can I use a map?" are questions; "I'm training for a marathon" is a statement.
    static func isFirstPersonStatement(_ message: String) -> Bool {
        guard message.count <= maxMessageLength else { return false }
        return message.split(whereSeparator: { ".!\n".contains($0) }).contains { sentence in
            !sentence.trimmingCharacters(in: .whitespaces).hasSuffix("?")
                && MemoryRecallLogic.words(String(sentence)).contains { firstPersonWords.contains($0) }
        }
    }

    /// What the model returned, kept only when it is a plain statement the message supports: not a question, not empty or
    /// over the length limit, sharing a word of three letters or more with the message (a model that invents shares none),
    /// no repeat, at most three.
    static func clean(_ raw: [String], message: String) -> [String] {
        let said = MemoryRecallLogic.contentTerms(message).filter { $0.count >= 3 }
        var seen = Set<String>()
        var kept: [String] = []
        for statement in raw.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard statement.contains(where: \.isLetter), statement.count <= MemoryKind.fact.textLimit, !statement.hasSuffix("?"),
                  !said.isDisjoint(with: MemoryRecallLogic.contentTerms(statement)),
                  seen.insert(statement.lowercased()).inserted else { continue }
            kept.append(statement)
            if kept.count == maxStatements { break }
        }
        return kept
    }
}
