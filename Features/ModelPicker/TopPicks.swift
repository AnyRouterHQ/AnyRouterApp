import Foundation

/// The short "Top picks" list on the AnyRouter tab: the most used models this week, or a bundled list
/// (`top-picks.json`) before the usage order is known. Only models the user can use.
struct TopPicksConfig: Codable, Equatable, Sendable {
    /// Used when the usage order is not available (offline, first launch).
    var fallback: [String]
    /// How many of the most used models to add.
    var usageCount: Int

    static let standard = TopPicksConfig(
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
    /// Usable cloud models only: the most used ones, else the bundled fallback list.
    static func compose(
        config: TopPicksConfig, models: [ModelDescriptor], usageRank: [String: Int]
    ) -> [ModelDescriptor] {
        let usable = models.filter { $0.source == .anyrouter && $0.isInstalled }
        let byWire = Dictionary(usable.map { ($0.wireID, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = usable
            .filter { usageRank[$0.wireID] != nil }
            .sorted { (usageRank[$0.wireID] ?? 0) < (usageRank[$1.wireID] ?? 0) }
        return ranked.isEmpty ? config.fallback.compactMap { byWire[$0] } : Array(ranked.prefix(config.usageCount))
    }
}
