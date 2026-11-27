import Foundation
import Observation

/// The replies being written in this process, whatever window writes them. A second iPad window on the same chat reads
/// it, so a reply streaming in the first window shows as streaming there, not as "stopped when the app closed" (the
/// interrupted marker every reply carries until it ends, agent design 1.3).
@MainActor @Observable
final class LiveReplies {
    static let shared = LiveReplies()

    private(set) var ids: Set<UUID> = []

    func begin(_ id: UUID) { ids.insert(id) }

    func end(_ id: UUID) { ids.remove(id) }
}
