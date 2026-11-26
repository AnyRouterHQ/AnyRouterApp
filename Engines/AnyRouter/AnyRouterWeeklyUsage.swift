import Foundation

/// `GET /api/v1/analytics/top-models?period=this_week`: each model's last 7 days, ranked by tokens. Public, no key needed.
struct AnyRouterWeeklyUsage: WeeklyUsageSource {
    var config: AnyRouterConfig = .standard
    var session: URLSession = .shared

    /// The server's ceiling for `limit`, so every model with traffic is listed.
    private static let limit = 500

    private struct Response: Decodable {
        struct Row: Decodable {
            var modelID: String
            var rank: Int
            var tokens: Int
            var requests: Int

            enum CodingKeys: String, CodingKey {
                case modelID = "model_id", rank, tokens, requests
            }
        }

        var models: [Row]
    }

    func fetchWeeklyUsage() async throws -> [ModelUsage] {
        var components = URLComponents(
            url: config.baseURL.appending(path: "analytics/top-models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "period", value: "this_week"),
            URLQueryItem(name: "limit", value: String(Self.limit)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(config.clientName, forHTTPHeaderField: "X-AnyRouter-Title")
        let (data, response) = try await session.data(for: request)
        let status = AnyRouterError.status(of: response)
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        return try JSONDecoder().decode(Response.self, from: data).models
            .sorted { $0.rank < $1.rank }
            .map { ModelUsage(id: $0.modelID, rank: $0.rank, tokens: $0.tokens, requests: $0.requests) }
    }
}
