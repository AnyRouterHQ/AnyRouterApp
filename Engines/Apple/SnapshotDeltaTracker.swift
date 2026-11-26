import Foundation

/// `streamResponse` yields the whole answer so far. The `ChatEngine` contract wants
/// append-only suffixes, so this keeps what was already sent and returns only the new tail.
struct SnapshotDeltaTracker {
    private var sent = ""
    private var restartPending = false

    /// Call after a tool ran. If the next snapshot is not a continuation of the text already sent,
    /// the model started a new segment: it is appended after a blank line instead of being
    /// sliced at the old length, which would drop or garble its start.
    mutating func markToolBoundary() {
        if !sent.isEmpty { restartPending = true }
    }

    mutating func delta(for snapshot: String) -> String? {
        var lead = ""
        if restartPending, !snapshot.isEmpty {
            restartPending = false
            if !snapshot.hasPrefix(sent) {
                lead = "\n\n"
                sent = ""
            }
        }
        if snapshot.hasPrefix(sent) {
            let tail = lead + String(snapshot.dropFirst(sent.count))
            sent = snapshot
            return tail.isEmpty ? nil : tail
        }
        // The model rewrote earlier text. We cannot retract what was shown, so only
        // append whatever extends past what was already sent.
        guard snapshot.count > sent.count else { return nil }
        let tail = String(snapshot.dropFirst(sent.count))
        sent = snapshot
        return tail
    }
}
