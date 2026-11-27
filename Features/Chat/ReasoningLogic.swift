import Foundation

/// The reasoning a model wrote before its answer, kept with the reply. Display only: it is never sent back to a model.
struct ReasoningTrace: Codable, Equatable, Sendable {
    var text: String
    /// First reasoning text to the first word of the answer or the first tool call. Nil while the model is still
    /// thinking, and for a reply that was stopped before it ended.
    var durationMs: Int?
}

/// Cuts `<think>…</think>` out of a text stream, for models that write their reasoning inline (the local ones).
/// Only a block at the very start of the reply counts; a later "<think>" is part of the answer. A tag split across
/// two pieces is held back until it is complete, so it never shows up as text.
struct ReasoningSplitter: Equatable {
    struct Output: Equatable {
        var reasoning = ""
        var text = ""
    }

    private enum State { case start, thinking, answer }
    private static let open = "<think>"
    private static let close = "</think>"

    private var state = State.start
    private var held = ""
    private var trimsLead = false

    mutating func feed(_ piece: String) -> Output {
        var output = Output()
        var buffer = held + piece
        held = ""
        var finished = false
        while !finished {
            switch state {
            case .start:
                let lead = buffer.drop(while: \.isWhitespace)
                if lead.hasPrefix(Self.open) {
                    buffer = String(lead.dropFirst(Self.open.count))
                    state = .thinking
                } else if lead.isEmpty || Self.open.hasPrefix(lead) {
                    held = buffer
                    finished = true
                } else {
                    state = .answer
                }
            case .thinking:
                if let range = buffer.range(of: Self.close) {
                    output.reasoning += buffer[..<range.lowerBound]
                    buffer = String(buffer[range.upperBound...])
                    state = .answer
                    trimsLead = true
                } else {
                    let keep = Self.partialTag(Self.close, endingIn: buffer)
                    output.reasoning += buffer.dropLast(keep)
                    held = String(buffer.suffix(keep))
                    finished = true
                }
            case .answer:
                var text = buffer
                if trimsLead {
                    text = String(buffer.drop(while: \.isWhitespace))
                    if !text.isEmpty { trimsLead = false }
                }
                output.text += text
                finished = true
            }
        }
        return output
    }

    /// The stream ended: whatever was held back is what it was, text before a tag started, reasoning after one did.
    mutating func finish() -> Output {
        defer { held = "" }
        return state == .thinking ? Output(reasoning: held) : Output(text: held)
    }

    /// How many characters at the end of `text` are the start of `tag`.
    private static func partialTag(_ tag: String, endingIn text: String) -> Int {
        var length = min(tag.count - 1, text.count)
        while length > 0 {
            if text.hasSuffix(tag.prefix(length)) { return length }
            length -= 1
        }
        return 0
    }
}

/// Collects the reasoning of one reply and times it.
struct ReasoningRecorder: Equatable {
    private var text = ""
    private var startedAt: TimeInterval?
    private var endedAt: TimeInterval?

    mutating func add(_ piece: String, at time: TimeInterval) {
        guard !piece.isEmpty else { return }
        if startedAt == nil { startedAt = time }
        text += piece
    }

    /// The model went on to its answer or a tool call. The first call counts; no reasoning, no effect.
    mutating func end(at time: TimeInterval) {
        if startedAt != nil, endedAt == nil { endedAt = time }
    }

    var hasEnded: Bool { endedAt != nil }

    /// Nil until some reasoning arrived.
    var trace: ReasoningTrace? {
        guard let startedAt else { return nil }
        return ReasoningTrace(text: text, durationMs: endedAt.map { max(0, Int((($0 - startedAt) * 1000).rounded())) })
    }
}

/// The words on the reasoning row.
enum ReasoningLogic {
    /// "Thinking…" while it writes, "Thought for 12s" after, "Thought" when the time is not known.
    static func title(durationMs: Int?, isStreaming: Bool) -> String {
        if isStreaming { return String(localized: "Thinking…") }
        guard let durationMs else { return String(localized: "Thought") }
        return String(localized: "Thought for \(duration(durationMs))")
    }

    /// "1s", "12s", "1m", "2m 5s". Never under a second.
    static func duration(_ ms: Int) -> String {
        let seconds = max(1, Int((Double(ms) / 1000).rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let rest = seconds % 60
        return rest == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(rest)s"
    }

    /// The last line written so far, cut to one line: what the collapsed row shows while the model thinks.
    static func latestLine(_ text: String, limit: Int = 80) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).last(where: { !$0.allSatisfy(\.isWhitespace) }) else {
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
