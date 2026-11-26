import Foundation

/// One model's last 7 days on AnyRouter. Comes from the public top-models statistics, which rank by tokens.
struct ModelUsage: Codable, Equatable, Sendable {
    /// Wire id (`<provider>/<model>`).
    var id: String
    /// 1 is the most used.
    var rank: Int
    var tokens: Int
    var requests: Int

    /// "12.4B tokens", or "34K requests" when the week has no token count.
    var summary: String {
        if tokens > 0 { return "\(PriceFormat.compactCount(tokens)) \(tokens == 1 ? "token" : "tokens")" }
        return "\(PriceFormat.compactCount(requests)) \(requests == 1 ? "request" : "requests")"
    }

    /// "12.4B tokens this week".
    var weeklySummary: String { summary + " this week" }
}

/// Where the weekly usage comes from. AnyRouter's adapter calls `GET /analytics/top-models`.
protocol WeeklyUsageSource: Sendable {
    /// Most used first.
    func fetchWeeklyUsage() async throws -> [ModelUsage]
}

/// The weekly usage, cached so the picker works offline.
struct WeeklyUsageCache {
    static let maxAge: TimeInterval = 6 * 3600
    private static let dataKey = "models.weeklyUsage.v1"
    private static let dateKey = "models.weeklyUsage.fetchedAt"

    let defaults: UserDefaults

    /// Empty when nothing is cached or the saved data does not read back.
    func load() -> [ModelUsage] {
        guard let data = defaults.data(forKey: Self.dataKey),
              let usage = try? JSONDecoder().decode([ModelUsage].self, from: data) else { return [] }
        return usage
    }

    func isFresh(now: Date) -> Bool {
        guard let date = defaults.object(forKey: Self.dateKey) as? Date, !load().isEmpty else { return false }
        return now.timeIntervalSince(date) < Self.maxAge
    }

    func save(_ usage: [ModelUsage], at date: Date) {
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.dataKey) }
        defaults.set(date, forKey: Self.dateKey)
    }
}
