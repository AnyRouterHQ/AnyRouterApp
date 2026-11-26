import Foundation

/// A starter question or task the user can drop into the composer.
struct PromptPreset: Identifiable, Codable, Hashable, Sendable {
    enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
        case learn, write, plan, code, explore
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var id: String
    var title: String
    var prompt: String
    var category: Category
    /// SF Symbol name.
    var symbol: String
}

/// Pure list logic for the presets UI, kept apart from views so it is testable.
enum PresetLogic {
    static func filter(_ items: [PromptPreset], category: PromptPreset.Category?, query: String = "") -> [PromptPreset] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (category == nil || item.category == category)
                && (needle.isEmpty
                    || item.title.localizedCaseInsensitiveContains(needle)
                    || item.prompt.localizedCaseInsensitiveContains(needle))
        }
    }

    /// Same day and salt give the same order. The salt moves on each "Shuffle" tap.
    static func shuffled(_ items: [PromptPreset], seed: UInt64) -> [PromptPreset] {
        var rng = SplitMix64(seed: seed)
        return items.shuffled(using: &rng)
    }

    static func daySeed(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
    }

    /// Custom presets stay first; the shuffle only reorders the rest.
    static func featured(_ items: [PromptPreset], customIDs: Set<String>, category: PromptPreset.Category?,
                         seed: UInt64, limit: Int) -> [PromptPreset] {
        let filtered = filter(items, category: category)
        let custom = filtered.filter { customIDs.contains($0.id) }
        let rest = shuffled(filtered.filter { !customIDs.contains($0.id) }, seed: seed)
        return Array((custom + rest).prefix(limit))
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
