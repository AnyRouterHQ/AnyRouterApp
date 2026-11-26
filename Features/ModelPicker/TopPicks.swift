import Foundation

/// The short "Top picks" list on the AnyRouter tab. The curated part is data (`top-picks.json`);
/// the live usage order and the user's availability are merged in.
struct TopPicksConfig: Codable, Equatable, Sendable {
    /// Wire ids that always lead, in order (the routers).
    var curated: [String]
    /// Used when the usage order is not available (offline, first launch).
    var fallback: [String]
    /// How many of the most used models to add.
    var usageCount: Int

    static let standard = TopPicksConfig(
        curated: ["anyrouter/auto", "anyrouter/free"],
        fallback: ["anthropic/claude-sonnet-4-6", "openai/gpt-5", "google/gemini-2.5-pro"],
        usageCount: 3)

    /// The bundled file, or `standard` when it is missing or unreadable.
    static func bundled(_ bundle: Bundle = .main) -> TopPicksConfig {
        guard let url = bundle.url(forResource: "top-picks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(TopPicksConfig.self, from: data) else { return .standard }
        return config
    }
}

enum TopPicks {
    /// Usable cloud models only: curated routers, then the most used models (skipping routers),
    /// else the bundled fallback list. No duplicates.
    static func compose(
        config: TopPicksConfig, models: [ModelDescriptor], usageRank: [String: Int]
    ) -> [ModelDescriptor] {
        let usable = models.filter { $0.source == .anyrouter && $0.isInstalled }
        let byWire = Dictionary(usable.map { ($0.wireID, $0) }, uniquingKeysWith: { first, _ in first })
        var picks: [ModelDescriptor] = config.curated.compactMap { byWire[$0] }

        let ranked = usable
            .filter { !$0.isRouter && usageRank[$0.wireID] != nil }
            .sorted { (usageRank[$0.wireID] ?? 0) < (usageRank[$1.wireID] ?? 0) }
        let extra = ranked.isEmpty ? config.fallback.compactMap { byWire[$0] } : Array(ranked.prefix(config.usageCount))
        for model in extra where !picks.contains(where: { $0.id == model.id }) {
            picks.append(model)
        }
        return picks
    }
}

/// The server's usage order (7-day request volume), cached so the picker works offline.
struct UsageOrderCache {
    static let maxAge: TimeInterval = 6 * 3600
    private static let idsKey = "models.usageOrder.ids"
    private static let dateKey = "models.usageOrder.fetchedAt"

    let defaults: UserDefaults

    func load() -> [String] { defaults.stringArray(forKey: Self.idsKey) ?? [] }

    func isFresh(now: Date) -> Bool {
        guard let date = defaults.object(forKey: Self.dateKey) as? Date, !load().isEmpty else { return false }
        return now.timeIntervalSince(date) < Self.maxAge
    }

    func save(_ ids: [String], at date: Date) {
        defaults.set(ids, forKey: Self.idsKey)
        defaults.set(date, forKey: Self.dateKey)
    }
}

/// Where the usage order comes from. AnyRouter's adapter calls `GET /models?sort=usage`.
protocol UsageOrderSource: Sendable {
    /// Wire ids, most used first.
    func fetchUsageOrder() async throws -> [String]
}
