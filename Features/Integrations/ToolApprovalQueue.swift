import Foundation

/// Requests waiting for the user, oldest first. The first one is shown; the rest wait their turn.
struct ToolApprovalQueue {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let request: ToolApprovalRequest
    }

    private(set) var entries: [Entry] = []
    /// Cancel notices that arrived before their request was queued.
    private var cancelledEarly: Set<UUID> = []

    var current: Entry? { entries.first }

    /// False when the caller was cancelled before the request arrived: it must not be shown.
    mutating func enqueue(_ entry: Entry) -> Bool {
        if cancelledEarly.remove(entry.id) != nil { return false }
        entries.append(entry)
        return true
    }

    /// Drops a request. True when it was queued; false means it has not arrived yet, so it is refused on arrival.
    @discardableResult
    mutating func remove(id: UUID, markIfMissing: Bool = false) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            if markIfMissing { cancelledEarly.insert(id) }
            return false
        }
        entries.remove(at: index)
        return true
    }
}
