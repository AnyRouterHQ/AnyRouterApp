import Foundation

/// The two-level model browser's rules, with no UI: grouping, fit summaries, the recommended size, sorting and filtering.
enum FamilyLogic {
    // MARK: Grouping

    /// Families in catalog order, from the entries of the catalog. Deprecated entries and entries with no family are left out.
    static func families(from entries: [LocalModelEntry]) -> [LocalModelFamily] {
        var order: [String] = []
        var grouped: [String: [LocalModelEntry]] = [:]
        for entry in entries where !entry.isDeprecated {
            guard let id = entry.familyID else { continue }
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let variants = grouped[id], let first = variants.first else { return nil }
            return LocalModelFamily(
                id: id, name: first.familyName ?? id, publisher: first.publisher ?? "", logo: first.logo ?? "",
                summary: first.summary, website: first.website,
                tags: tags(from: variants.reduce(into: Set<String>()) { $0.formUnion($1.descriptor.capabilities) }),
                badges: first.badges.map { $0.label.lowercased() },
                variants: variants)
        }
    }

    /// Entries that belong to no family and are not deprecated.
    static func ungrouped(_ entries: [LocalModelEntry]) -> [LocalModelEntry] {
        entries.filter { $0.familyID == nil && !$0.isDeprecated }
    }

    /// Catalog tag names for a set of capabilities: everything but plain chat, with "reasoning" shown as "thinking".
    static func tags(from capabilities: Set<String>) -> [String] {
        capabilities.subtracting(["chat"]).map { $0 == "reasoning" ? "thinking" : $0 }.sorted()
    }

    // MARK: Fit

    /// A size the device can run: not too big, and not blocked for another reason (MLX in the Simulator).
    static func canRun(_ entry: LocalModelEntry) -> Bool {
        entry.fit != .wontFit && entry.unavailableReason == nil
    }

    /// "3 of 4 sizes fit" for the family row.
    static func fitSummary(_ family: LocalModelFamily, device: String) -> String {
        let total = family.variants.count
        let fitting = family.variants.filter(canRun).count
        switch (fitting, total) {
        case (0, _): return "No size fits this \(device)"
        case (let n, let t) where n == t && t == 1: return "Fits this \(device)"
        case (let n, let t) where n == t: return "All \(t) sizes fit"
        case (let n, let t): return "\(n) of \(t) sizes fit"
        }
    }

    // MARK: Recommended

    /// The best size for this device: among the sizes that run well (with headroom), the biggest model; on a tie the
    /// GGUF one (the engine tested the most), then the larger file. Nil when nothing runs well.
    static func recommendedVariantID(in family: LocalModelFamily) -> String? {
        let candidates = family.variants.filter { $0.fit == .fits && $0.unavailableReason == nil }
        return candidates.max { quality($0) < quality($1) }?.id
    }

    /// The short list at the top of the local models: each family's recommended size, with catalog top picks first, then by
    /// quality (bigger model, GGUF, bigger file). At most `limit`.
    static func recommendedEntries(from families: [LocalModelFamily], limit: Int = 5) -> [LocalModelEntry] {
        let picks: [(entry: LocalModelEntry, topPick: Bool)] = families.compactMap { family in
            guard let id = recommendedVariantID(in: family), let entry = family.variants.first(where: { $0.id == id })
            else { return nil }
            return (entry, isTopPick(family))
        }
        let ordered = picks.enumerated().sorted { l, r in
            if l.element.topPick != r.element.topPick { return l.element.topPick }
            let (a, b) = (quality(l.element.entry), quality(r.element.entry))
            return a == b ? l.offset < r.offset : a > b
        }
        return ordered.prefix(max(0, limit)).map(\.element.entry)
    }

    /// Compared in order: parameter count, GGUF over MLX, then file size. Tuples of Comparable compare lexicographically.
    private static func quality(_ entry: LocalModelEntry) -> (Double, Int, Int64) {
        (entry.parameterBillions ?? 0, entry.descriptor.source == .gguf ? 1 : 0, entry.descriptor.sizeBytes ?? 0)
    }

    /// Parses "4B", "E2B", "0.6B", "700M" into billions. Nil when it is not a size.
    static func billions(of parameters: String?) -> Double? {
        guard let parameters else { return nil }
        var text = parameters.trimmingCharacters(in: .whitespaces).uppercased()
        if text.hasPrefix("E") { text.removeFirst() }
        guard let unit = text.last, "BM".contains(unit), let value = Double(text.dropLast()), value > 0 else { return nil }
        return unit == "B" ? value : value / 1000
    }

    // MARK: Sort

    /// Whether the family carries a top-pick badge from the catalog.
    static func isTopPick(_ family: LocalModelFamily) -> Bool {
        !Set(family.badges).isDisjoint(with: ["best", "recommended"])
    }

    static func smallestSize(_ family: LocalModelFamily) -> Int64 {
        family.variants.compactMap(\.descriptor.sizeBytes).min() ?? .max
    }

    static func newestDate(_ family: LocalModelFamily) -> String {
        family.variants.compactMap(\.releasedAt).max() ?? ""
    }

    // MARK: Sort and filter

    /// Families with at least one size that passes the filter, in the chosen order. The sizes are not narrowed here:
    /// the family row summarizes all of them, and `variants(of:filter:)` gives the ones to show in the detail.
    static func apply(_ families: [LocalModelFamily], sort: FamilySort, filter: FamilyFilter) -> [LocalModelFamily] {
        let kept = Array(families.enumerated().filter { _, family in
            filter.keeps(tags: family.tags) && family.variants.contains { filter.keeps($0) }
        })
        func by(_ areInIncreasingOrder: (LocalModelFamily, LocalModelFamily) -> Bool?) -> [LocalModelFamily] {
            kept.sorted { l, r in areInIncreasingOrder(l.element, r.element) ?? (l.offset < r.offset) }.map(\.element)
        }
        switch sort {
        case .recommended:
            func rank(_ family: LocalModelFamily) -> Int {
                if isTopPick(family) { return 0 }
                return recommendedVariantID(in: family) != nil ? 1 : 2
            }
            return by { rank($0) == rank($1) ? nil : rank($0) < rank($1) }
        case .smallest:
            return by { smallestSize($0) == smallestSize($1) ? nil : smallestSize($0) < smallestSize($1) }
        case .newest:
            return by { newestDate($0) == newestDate($1) ? nil : newestDate($0) > newestDate($1) }
        case .name:
            return by {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? nil : order == .orderedAscending
            }
        }
    }

    /// The sizes of one family to show in its detail, smallest model first, GGUF before MLX at the same size.
    static func variants(of family: LocalModelFamily, filter: FamilyFilter) -> [LocalModelEntry] {
        family.variants.filter { filter.keeps($0) }.enumerated().sorted { l, r in
            let (a, b) = (l.element.parameterBillions ?? 0, r.element.parameterBillions ?? 0)
            if a != b { return a < b }
            let (x, y) = (l.element.descriptor.source == .gguf, r.element.descriptor.source == .gguf)
            if x != y { return x }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// Tags worth a filter toggle: the ones some family has.
    static func tags(in families: [LocalModelFamily]) -> [String] {
        Set(families.flatMap(\.tags)).sorted()
    }
}

enum FamilySort: String, CaseIterable, Identifiable, Sendable {
    case recommended, smallest, newest, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .smallest: "Smallest"
        case .newest: "Newest"
        case .name: "Name"
        }
    }
}

enum SizeBucket: String, CaseIterable, Identifiable, Sendable {
    case underOneGB, oneToFourGB, overFourGB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .underOneGB: "Under 1 GB"
        case .oneToFourGB: "1 to 4 GB"
        case .overFourGB: "Over 4 GB"
        }
    }

    /// Decimal gigabytes, as the file sizes are shown.
    func contains(_ bytes: Int64) -> Bool {
        switch self {
        case .underOneGB: bytes < 1_000_000_000
        case .oneToFourGB: bytes >= 1_000_000_000 && bytes < 4_000_000_000
        case .overFourGB: bytes >= 4_000_000_000
        }
    }
}

/// What the browser hides. Empty sets mean no restriction. "Fits this device" starts on.
struct FamilyFilter: Equatable, Sendable {
    var fitsOnly = true
    var engines: Set<ModelSource> = []
    var tags: Set<String> = []
    var sizes: Set<SizeBucket> = []

    /// True when the filter differs from what the screen starts with.
    var isChanged: Bool { self != FamilyFilter() }

    /// A family must have every selected tag.
    func keeps(tags familyTags: [String]) -> Bool {
        tags.isSubset(of: Set(familyTags))
    }

    /// One size passes the fit, engine and size-bucket filters.
    func keeps(_ entry: LocalModelEntry) -> Bool {
        if fitsOnly && !FamilyLogic.canRun(entry) { return false }
        if !engines.isEmpty && !engines.contains(entry.descriptor.source) { return false }
        if !sizes.isEmpty && !sizes.contains(where: { $0.contains(entry.descriptor.sizeBytes ?? 0) }) { return false }
        return true
    }
}
