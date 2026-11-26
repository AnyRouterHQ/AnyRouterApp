import Foundation

/// How the Manage models list is ordered.
enum HubSort: String, CaseIterable, Identifiable, Sendable {
    case recommended, name, smallest, largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .name: "Name"
        case .smallest: "Smallest first"
        case .largest: "Largest first"
        }
    }
}

/// What the Manage models list hides. Empty sets mean "no restriction".
struct HubFilter: Equatable, Sendable {
    /// Hide models that will not load on this device or cannot run here.
    var fitsOnly = false
    var engines: Set<ModelSource> = []
    /// A model must have every capability listed.
    var capabilities: Set<String> = []

    var isActive: Bool { fitsOnly || !engines.isEmpty || !capabilities.isEmpty }
}

/// View-layer ordering, filtering and row text for Manage models. Pure, so it is tested without UI.
enum HubListOptions {
    static func apply(_ entries: [LocalModelEntry], sort: HubSort, filter: HubFilter) -> [LocalModelEntry] {
        let kept = entries.filter { keeps($0, filter) }
        let indexed = Array(kept.enumerated())
        func size(_ entry: LocalModelEntry) -> Int64 { entry.descriptor.sizeBytes ?? .max }
        let ordered: [(offset: Int, element: LocalModelEntry)]
        switch sort {
        case .recommended:
            ordered = indexed.sorted { l, r in
                if l.element.isRecommended != r.element.isRecommended { return l.element.isRecommended }
                return l.offset < r.offset
            }
        case .name:
            ordered = indexed.sorted { l, r in
                let order = l.element.descriptor.displayName.localizedCaseInsensitiveCompare(r.element.descriptor.displayName)
                return order == .orderedSame ? l.offset < r.offset : order == .orderedAscending
            }
        case .smallest:
            ordered = indexed.sorted { l, r in
                size(l.element) == size(r.element) ? l.offset < r.offset : size(l.element) < size(r.element)
            }
        case .largest:
            ordered = indexed.sorted { l, r in
                let (a, b) = (l.element.descriptor.sizeBytes ?? 0, r.element.descriptor.sizeBytes ?? 0)
                return a == b ? l.offset < r.offset : a > b
            }
        }
        return ordered.map(\.element)
    }

    static func keeps(_ entry: LocalModelEntry, _ filter: HubFilter) -> Bool {
        if filter.fitsOnly && (entry.fit == .wontFit || entry.unavailableReason != nil) { return false }
        if !filter.engines.isEmpty && !filter.engines.contains(entry.descriptor.source) { return false }
        return filter.capabilities.isSubset(of: entry.descriptor.capabilities)
    }

    /// Capabilities worth a filter toggle: everything the catalog lists except plain "chat".
    static func capabilities(in entries: [LocalModelEntry]) -> [String] {
        Set(entries.flatMap(\.descriptor.capabilities)).subtracting(["chat"]).sorted()
    }

    static func engineName(_ source: ModelSource) -> String {
        switch source {
        case .gguf: "GGUF"
        case .mlx: "MLX"
        case .apple: "Apple"
        case .anyrouter: "AnyRouter"
        }
    }

    /// "GGUF · 4B · Q4_K_M · 2.5 GB · Uses ~3.1 GB": format, up to two catalog tags, file size, memory.
    static func detailLine(_ entry: LocalModelEntry) -> String {
        var parts = [engineName(entry.descriptor.source)]
        parts += entry.tags.dropFirst().prefix(2)
        if let size = HubLogic.sizeText(entry.descriptor.sizeBytes) { parts.append(size) }
        if let detail = entry.fitDetail { parts.append("Uses ~\(FitFormat.gigabytes(detail.neededBytes))") }
        return parts.joined(separator: " · ")
    }

    /// Short fit status for a row, or nil when nothing is known. `device` is "iPhone" or "iPad".
    static func fitStatus(_ entry: LocalModelEntry, device: String) -> String? {
        if let reason = entry.unavailableReason { return reason }
        if let detail = entry.fitDetail, let badge = FitText.badge(detail, device: device) { return badge }
        switch entry.fit {
        case .fits: return "Runs well"
        case .tight: return "Short context"
        case .wontFit: return "Too big for this \(device)"
        case .unknown: return nil
        }
    }

    static func storageSummary(usedBytes: Int64, freeBytes: Int64?) -> String {
        var text = "Models use \(FitFormat.gigabytes(usedBytes))"
        if let freeBytes { text += " · \(FitFormat.gigabytes(freeBytes)) free" }
        return text
    }
}
