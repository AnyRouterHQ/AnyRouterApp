import Foundation

/// The always-on profile (agent design 2.4): pinned notes, preferences and About you items as a short list after the
/// instructions. A chat freezes which items it uses at its first send, so the start of its prompt stays the same across
/// turns and relaunches. Items are frozen by id: one deleted since then leaves the next request.
enum MemoryProfileLogic {
    struct Item: Equatable, Sendable {
        let id: UUID
        let kind: MemoryKind
        let text: String
        let scope: MemoryScope
        let createdAt: Date
    }

    /// The order items meet the budget: pinned notes, then preferences, then About you; newest first in each.
    static let kinds: [MemoryKind] = [.note, .preference, .profile]

    /// Short: on Apple it shares 120 tokens with the items.
    static let heading = "About the user, from memory:"

    /// The items a chat that starts now keeps for its whole life, in the order they meet the budget.
    static func frozenIDs(_ items: [Item]) -> [UUID] {
        kinds.flatMap { kind in items.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt } }.map(\.id)
    }

    /// Whether a model runs off this device, for memory scope: AnyRouter models, and Apple Intelligence on Private Cloud
    /// Compute. The user's "this device" means this device; Apple's servers are not it, however private (PLAN D34).
    static func isCloud(_ model: ModelDescriptor) -> Bool {
        model.source == .anyrouter || model.id == ApplePCCLogic.modelID
    }

    /// A cloud model gets items learned in on-device chats only when the user allowed it.
    static func allows(_ scope: MemoryScope, toCloud: Bool, deviceMemoriesInCloud: Bool) -> Bool {
        !toCloud || scope == .everywhere || deviceMemoriesInCloud
    }

    /// The profile, or nil when no item is left. Items go in whole; one that does not fit is left out, never cut.
    static func render(
        _ items: [Item], frozen: [UUID], toCloud: Bool, deviceMemoriesInCloud: Bool, budget: Int
    ) -> String? {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var lines = [heading]
        for id in frozen {
            guard let item = byID[id], allows(item.scope, toCloud: toCloud, deviceMemoriesInCloud: deviceMemoriesInCloud) else { continue }
            let candidate = lines + ["- " + item.text]
            if TokenCountLogic.estimate(candidate.joined(separator: "\n")) <= budget { lines = candidate }
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }
}
