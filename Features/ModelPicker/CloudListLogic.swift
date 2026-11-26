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

/// How the AnyRouter tab is ordered. Top this week uses the server's 7-day usage ranking (by tokens).
enum PickerSort: String, CaseIterable, Identifiable {
    case topUsage, newest, cheapest, free, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topUsage: "Top this week"
        case .newest: "Newest"
        case .cheapest: "Cheapest"
        case .free: "Free"
        case .name: "Name"
        }
    }
}

/// Everything the AnyRouter tab shows: the models the person starred, a short curated section, then the rest in the chosen order.
struct CloudList: Equatable {
    var topPicks: [ModelDescriptor]
    var rest: [ModelDescriptor]
    /// Starred models that can be used, in the order they were starred. They lead the list.
    var starred: [ModelDescriptor] = []
    /// The short view only: AnyRouter's own routers, then `rest` holds the top models of the week.
    var routers: [ModelDescriptor] = []
    /// The short view only: the model in use when it is not on the list, so it never disappears.
    var current: ModelDescriptor? = nil
    /// The short view only: how many more models "Show all models" adds.
    var moreCount = 0
    var isShort = false

    var isEmpty: Bool { starred.isEmpty && topPicks.isEmpty && rest.isEmpty && routers.isEmpty && current == nil }
}

enum CloudListLogic {
    /// How many models the short view lists under "Top this week".
    static let topCount = 10

    /// `usageRank` maps a wire id to its place in the weekly usage order (0 is most used).
    /// `showUnusable` keeps models the user cannot route to (dimmed, after the usable ones).
    static func arrange(
        models: [ModelDescriptor], query: String, sort: PickerSort,
        usageRank: [String: Int], showUnusable: Bool, picks: [ModelDescriptor] = [],
        filter: ModelFilter = ModelFilter(), prefs: CloudModelPrefs = CloudModelPrefs(),
        currentID: String? = nil, short: Bool = false
    ) -> CloudList {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !needle.isEmpty
        var candidates = models.filter { model in
            guard model.source == .anyrouter else { return false }
            // "Hide needs-key models" does not apply to a search, so a search still finds them.
            let showLocked = showUnusable && (!filter.hideNeedsKey || searching)
            if !showLocked && !model.isInstalled { return false }
            if !filter.matches(model) { return false }
            // A hidden model stays out of the lists. A search still finds it, so it can be brought back.
            if !searching && prefs.isHidden(model) { return false }
            if sort == .free && model.cloud?.pricing.isFree != true { return false }
            if searching { return ModelPickerLogic.matches(model, needle) }
            return model.id != ModelDescriptor.byokRouterID
        }
        candidates.sort { lhs, rhs in
            // Usable models first, then the chosen order.
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
            return precedes(lhs, rhs, sort: sort, usageRank: usageRank)
        }
        let starred = searching ? [] : prefs.starred.compactMap { wire in candidates.first { $0.wireID == wire && $0.isInstalled } }
        let starredIDs = Set(starred.map(\.id))
        // A search always looks through the whole catalog.
        if short && !searching {
            return shortList(models: models, candidates: candidates, starred: starred, usageRank: usageRank, currentID: currentID)
        }
        let topPicks = searching ? [] : picks.filter { pick in
            !starredIDs.contains(pick.id) && candidates.contains { $0.id == pick.id }
        }
        let shownIDs = starredIDs.union(topPicks.map(\.id))
        return CloudList(topPicks: topPicks, rest: candidates.filter { !shownIDs.contains($0.id) }, starred: starred)
    }

    /// Routers, the top models of the week, the model in use, and a count of what "Show all models" adds.
    /// `candidates` are already filtered and in the chosen order. Starred models stay in their own section.
    private static func shortList(
        models: [ModelDescriptor], candidates: [ModelDescriptor], starred: [ModelDescriptor],
        usageRank: [String: Int], currentID: String?
    ) -> CloudList {
        let starredIDs = Set(starred.map(\.id))
        let routers = candidates.filter { $0.isRouter && !starredIDs.contains($0.id) }
        let others = candidates.filter { !$0.isRouter }
        // Before the first usage fetch lands nothing is ranked, so the list falls back to the chosen order.
        let ranked = others.filter { usageRank[$0.wireID] != nil }
        let top = Array((ranked.isEmpty ? others : ranked).prefix(topCount))
        let rest = top.filter { !starredIDs.contains($0.id) }
        let listed = starredIDs.union(routers.map(\.id)).union(top.map(\.id))
        let current = models.first { $0.id == currentID && $0.source == .anyrouter && $0.isInstalled && !listed.contains($0.id) }
        let more = candidates.filter { !listed.contains($0.id) && $0.id != current?.id }
        return CloudList(
            topPicks: [], rest: rest, starred: starred, routers: routers, current: current,
            moreCount: more.count, isShort: true)
    }

    /// The weekly usage a row shows. Only "Top this week" shows it, because only there the rows follow that ranking.
    static func rowUsage(of model: ModelDescriptor, sort: PickerSort, in usage: [String: ModelUsage]) -> ModelUsage? {
        sort == .topUsage ? usage[model.wireID] : nil
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
