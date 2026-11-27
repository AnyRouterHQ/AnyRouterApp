import Foundation

/// One line for a reply that used tools, sent with that reply's text on every later request (agent design 3.4), so
/// "read the second page again" works without replaying results. Derived from the stored steps the same way each time,
/// so a turn's text never changes after it was first sent.
enum ToolDigestLogic {
    static let maxCalls = 3

    static func digest(_ steps: [ToolStep]) -> String? {
        guard !steps.isEmpty else { return nil }
        var parts = steps.prefix(maxCalls).map(ToolRowLogic.title(for:))
        if steps.count > maxCalls { parts.append(String(localized: "and \(steps.count - maxCalls) more")) }
        return "[Tools: " + parts.joined(separator: "; ") + "]"
    }

    /// The chat as a model reads it: each reply that used tools ends with its digest.
    static func turns(_ messages: [ChatMessage], steps: [UUID: [ToolStep]]) -> [ChatMessage] {
        messages.map { message in
            guard let line = steps[message.id].flatMap(digest) else { return message }
            var copy = message
            copy.content += "\n\n" + line
            return copy
        }
    }
}
