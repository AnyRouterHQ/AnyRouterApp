import Foundation

/// A stretch of a chat folded into a short summary, so the chat can go on in a small context window. The messages
/// stay in the chat and on screen above the divider; only what is sent to the model changes.
struct Compaction: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// This message and every one before it are covered by `summary`.
    var lastMessageID: UUID
    var summary: String
    /// How many messages the summary stands for, earlier compactions included.
    var droppedCount: Int
    var createdAt: Date
}

/// What one compaction folds: the oldest messages that fit the summarizer, and the summary they extend.
struct CompactionPlan: Equatable {
    var messages: [ChatMessage]
    var lastMessageID: UUID
    var previousSummary: String?
    var previousDropped: Int
}

/// When to compact, what to fold and what to send afterwards. Pure: the chat only runs the summary request.
enum CompactionLogic {
    /// Compact when the chat uses this share of the model's window.
    static let threshold = 0.8
    /// Messages kept as they are: two exchanges when the window is filling up, one when the reader asks.
    static let keepRecentAutomatic = 4
    static let keepRecentManual = 2
    /// Folding fewer messages than this saves nothing.
    static let minimumToFold = 2
    /// The summary is asked to stay within this many tokens.
    static let summaryTokens = 400
    static let maxSummaryCharacters = 3_000
    /// A message longer than this is cut when it goes into the summary request.
    static let maxMessageCharacters = 6_000
    /// Window assumed for a manual compaction when the model's is not known.
    static let defaultWindow = 8_192

    static let summarizerPrompt = """
        You shorten a conversation so it can continue with less text. Write brief plain sentences or short bullets. \
        Keep names, numbers, decisions, file names, open questions and what the user prefers. Add nothing new. \
        Reply with the summary only.
        """

    /// A few tokens per message for its role.
    private static let perMessageTokens = 4

    /// The room a model has for one chat, in tokens. A local model is held to what the device can run (`FitPlanner`),
    /// not to the length it was trained for. Nil when the model does not say.
    static func window(for model: ModelDescriptor) -> Int? {
        guard let length = model.contextLength, length > 0 else { return nil }
        switch model.source {
        case .gguf, .mlx: return min(length, FitPlanner.maxContext)
        default: return length
        }
    }

    /// The compaction that applies, and the messages after the one it ends at. A compaction whose last message is gone
    /// from the chat does not apply, and everything is sent.
    static func live(messages: [ChatMessage], compaction: Compaction?) -> (applied: Compaction?, messages: [ChatMessage]) {
        guard let compaction, let index = messages.firstIndex(where: { $0.id == compaction.lastMessageID }) else {
            return (nil, messages)
        }
        return (compaction, Array(messages[(index + 1)...]))
    }

    /// What a request carries of the chat: the summary of the folded part and the messages after it.
    static func context(messages: [ChatMessage], compaction: Compaction?) -> (summary: String?, messages: [ChatMessage]) {
        let result = live(messages: messages, compaction: compaction)
        return (result.applied?.summary, result.messages)
    }

    /// The system prompt with the summary after it.
    static func systemPrompt(base: String?, summary: String?) -> String? {
        guard let summary else { return base }
        let note = "Earlier in this conversation (older messages were shortened into this summary):\n\(summary)"
        guard let base, !base.isEmpty else { return note }
        return base + "\n\n" + note
    }

    /// What a request would take up.
    static func usedTokens(systemPrompt: String?, summary: String?, messages: [ChatMessage]) -> Int {
        var total = 0
        for text in [systemPrompt, summary].compactMap({ $0 }) { total += TokenCountLogic.estimate(text) }
        for message in messages { total += TokenCountLogic.estimate(message.content) + perMessageTokens }
        return total
    }

    /// The share of the window a chat takes, 0.42 for 42%; above 1 when it no longer fits. Nil without a window.
    static func contextFraction(used: Int, window: Int?) -> Double? {
        guard let window, window > 0 else { return nil }
        return Double(used) / Double(window)
    }

    /// The meter in the chat menu: "42% of context used" and a gauge symbol whose needle follows it.
    static func meter(fraction: Double) -> (text: String, symbol: String) {
        let percent = Int((fraction * 100).rounded())
        let needle: String
        if fraction < 0.2 {
            needle = "0percent"
        } else if fraction < 0.45 {
            needle = "33percent"
        } else if fraction < 0.6 {
            needle = "50percent"
        } else if fraction < threshold {
            needle = "67percent"
        } else {
            needle = "100percent"
        }
        return (String(localized: "\(percent)% of context used"), "gauge.with.dots.needle.\(needle)")
    }

    static func needsCompaction(used: Int, window: Int?) -> Bool {
        guard let window else { return false }
        return Double(used) >= Double(window) * threshold
    }

    /// The oldest messages after the last compaction that fit the summarizer's share of the window (half of it), leaving
    /// `keepRecent` untouched. Nil when fewer than `minimumToFold` are left to fold.
    static func plan(messages: [ChatMessage], compaction: Compaction?, window: Int?, keepRecent: Int) -> CompactionPlan? {
        let (applied, remaining) = live(messages: messages, compaction: compaction)
        let candidates = remaining.dropLast(keepRecent)
        guard candidates.count >= minimumToFold else { return nil }
        let budget = (window ?? defaultWindow) / 2
        var used = 0
        var previousDropped = 0
        if let applied {
            used = TokenCountLogic.estimate(applied.summary)
            previousDropped = applied.droppedCount
        }
        var chosen: [ChatMessage] = []
        for message in candidates {
            let cost = TokenCountLogic.estimate(clipped(message.content)) + perMessageTokens
            if chosen.count >= minimumToFold, used + cost > budget { break }
            chosen.append(message)
            used += cost
        }
        return CompactionPlan(
            messages: chosen, lastMessageID: chosen[chosen.count - 1].id, previousSummary: applied?.summary,
            previousDropped: previousDropped)
    }

    /// The request that asks a model for the summary: its instructions and one message with the transcript.
    static func request(for plan: CompactionPlan) -> (system: String, messages: [ChatMessage]) {
        var text = ""
        if let previous = plan.previousSummary { text += "Summary so far:\n\(previous)\n\n" }
        text += "New messages:\n"
        for message in plan.messages {
            let speaker = message.role == .user ? "User" : "Assistant"
            text += "\(speaker): \(clipped(message.content))\n"
        }
        text += "\nWrite the updated summary."
        return (summarizerPrompt, [ChatMessage(role: .user, content: text)])
    }

    /// The model's answer as a summary: trimmed and capped. Nil when it wrote nothing.
    static func cleanSummary(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxSummaryCharacters))
    }

    static func record(summary: String, plan: CompactionPlan, now: Date) -> Compaction {
        Compaction(
            lastMessageID: plan.lastMessageID, summary: summary,
            droppedCount: plan.previousDropped + plan.messages.count, createdAt: now)
    }

    /// "12 earlier messages shortened".
    static func subtitle(droppedCount: Int) -> String {
        droppedCount == 1
            ? String(localized: "1 earlier message shortened")
            : String(localized: "\(droppedCount) earlier messages shortened")
    }

    private static func clipped(_ text: String) -> String {
        text.count > maxMessageCharacters ? String(text.prefix(maxMessageCharacters)) + "…" : text
    }
}
