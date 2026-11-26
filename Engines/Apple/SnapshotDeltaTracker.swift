import Foundation

/// `streamResponse` yields the whole answer so far. The `ChatEngine` contract wants
/// append-only suffixes, so this keeps what was already sent and returns only the new tail.
struct SnapshotDeltaTracker {
    private var sent = ""

    mutating func delta(for snapshot: String) -> String? {
        if snapshot.hasPrefix(sent) {
            let tail = String(snapshot.dropFirst(sent.count))
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
