import Foundation

/// The two tabs of the picker. The sheet opens on the tab of the current model.
enum PickerTab: String, CaseIterable, Identifiable {
    case local, anyrouter

    var id: String { rawValue }
    var title: String { self == .local ? "Local" : "AnyRouter" }

    static func tab(for model: ModelDescriptor?) -> PickerTab {
        model?.source == .anyrouter ? .anyrouter : .local
    }
}

/// How the AnyRouter tab is ordered. Top usage uses the server's 7-day request volume.
enum PickerSort: String, CaseIterable, Identifiable {
    case topUsage, newest, cheapest, free, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topUsage: "Top usage"
        case .newest: "Newest"
        case .cheapest: "Cheapest"
        case .free: "Free"
        case .name: "Name"
        }
    }
}

/// Everything the AnyRouter tab shows: a short curated section, then the rest in the chosen order.
struct CloudList: Equatable {
    var topPicks: [ModelDescriptor]
    var rest: [ModelDescriptor]

    var isEmpty: Bool { topPicks.isEmpty && rest.isEmpty }
}

enum CloudListLogic {
    /// `usageRank` maps a wire id to its place in the server's usage order (0 is most used).
    /// `showUnusable` keeps models the user cannot route to (dimmed, after the usable ones).
    static func arrange(
        models: [ModelDescriptor], query: String, sort: PickerSort,
        usageRank: [String: Int], showUnusable: Bool, picks: [ModelDescriptor] = [],
        filter: ModelFilter = ModelFilter()
    ) -> CloudList {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !needle.isEmpty
        var candidates = models.filter { model in
            guard model.source == .anyrouter else { return false }
            // "Hide needs-key models" does not apply to a search, so a search still finds them.
            let showLocked = showUnusable && (!filter.hideNeedsKey || searching)
            if !showLocked && !model.isInstalled { return false }
            if !filter.matches(model) { return false }
            if sort == .free && model.cloud?.pricing.isFree != true { return false }
            if searching { return ModelPickerLogic.matches(model, needle) }
            return model.id != ModelDescriptor.byokRouterID
        }
        candidates.sort { lhs, rhs in
            // Usable models first, then the chosen order.
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
            return precedes(lhs, rhs, sort: sort, usageRank: usageRank)
        }
        let topPicks = searching ? [] : picks.filter { pick in candidates.contains { $0.id == pick.id } }
        let pickIDs = Set(topPicks.map(\.id))
        return CloudList(topPicks: topPicks, rest: candidates.filter { !pickIDs.contains($0.id) })
    }

    private static func precedes(_ a: ModelDescriptor, _ b: ModelDescriptor, sort: PickerSort, usageRank: [String: Int]) -> Bool {
        func byName() -> Bool { a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending }
        func byUsage() -> Bool? {
            switch (usageRank[a.wireID], usageRank[b.wireID]) {
            case let (x?, y?): return x == y ? nil : x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        }
        // AnyRouter's own routers lead the usage and name orders ("AnyRouter" first).
        if sort == .topUsage || sort == .name, a.isRouter != b.isRouter { return a.isRouter }
        if sort == .topUsage || sort == .name, a.isRouter, b.isRouter { return routerRank(a) < routerRank(b) || (routerRank(a) == routerRank(b) && byName()) }
        switch sort {
        case .topUsage, .free:
            return byUsage() ?? byName()
        case .name:
            return byName()
        case .newest:
            switch (a.cloud?.created, b.cloud?.created) {
            case let (x?, y?): return x == y ? byName() : x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return byName()
            }
        case .cheapest:
            let (x, y) = (a.cloud?.pricing, b.cloud?.pricing)
            func key(_ p: CloudPricing?) -> (Decimal, Decimal)? {
                guard let p, let out = p.output, let input = p.input else { return nil }
                return (out, input)
            }
            switch (key(x), key(y)) {
            case let (l?, r?): return l == r ? byName() : (l.0 != r.0 ? l.0 < r.0 : l.1 < r.1)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return byName()
            }
        }
    }

    private static let routerOrder = ["auto", "free", "coding", "agent", "latest"]

    private static func routerRank(_ model: ModelDescriptor) -> Int {
        let slug = String(model.wireID.dropFirst("anyrouter/".count))
        return routerOrder.firstIndex(of: slug) ?? routerOrder.count
    }
}
