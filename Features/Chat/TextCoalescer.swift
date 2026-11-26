import Foundation

/// Batches streamed text so a fast model does not rebuild the message for every token.
/// The first piece goes through at once (the reply starts without delay); after that at most one update per `interval`.
struct TextCoalescer: Equatable {
    var interval: TimeInterval
    private var pending = ""
    private var lastFlush: TimeInterval?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Adds a piece. Returns the text to show now, or nil when it is held for the next update.
    mutating func add(_ piece: String, now: TimeInterval) -> String? {
        pending += piece
        if let last = lastFlush, now - last < interval { return nil }
        lastFlush = now
        return take()
    }

    /// Whatever is held back. Call before any other event and when the stream ends, so nothing is lost or reordered.
    mutating func flush() -> String? {
        pending.isEmpty ? nil : take()
    }

    private mutating func take() -> String {
        defer { pending = "" }
        return pending
    }
}
