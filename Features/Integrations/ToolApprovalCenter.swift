import Foundation
import Observation

/// Holds the tool approval the sheet shows and suspends each caller until the user decides.
/// Requests are served one at a time. A cancelled caller is denied and its request dropped.
@MainActor @Observable
final class ToolApprovalCenter: ToolApproving {
    private var queue = ToolApprovalQueue()
    @ObservationIgnored private var waiting: [UUID: CheckedContinuation<ToolDecision, Never>] = [:]

    /// The request on screen.
    var pending: ToolApprovalQueue.Entry? { queue.current }

    nonisolated func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor in self.enqueue(ToolApprovalQueue.Entry(id: id, request: request), continuation) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// The user's choice for the request on screen.
    func resolveCurrent(_ decision: ToolDecision) {
        guard let id = queue.current?.id else { return }
        resolve(id, decision)
    }

    private func enqueue(_ entry: ToolApprovalQueue.Entry, _ continuation: CheckedContinuation<ToolDecision, Never>) {
        guard queue.enqueue(entry) else {
            continuation.resume(returning: .deny)
            return
        }
        waiting[entry.id] = continuation
    }

    private func cancel(_ id: UUID) {
        if waiting[id] != nil {
            resolve(id, .deny)
        } else {
            queue.remove(id: id, markIfMissing: true)
        }
    }

    /// The continuation leaves the table before it resumes, so each one resumes once.
    private func resolve(_ id: UUID, _ decision: ToolDecision) {
        queue.remove(id: id)
        waiting.removeValue(forKey: id)?.resume(returning: decision)
    }
}
