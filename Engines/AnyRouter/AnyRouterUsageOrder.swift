import Foundation

/// `GET /api/v1/models?sort=usage`: ids ordered by 7-day request volume. Public, no key needed.
struct AnyRouterUsageOrder: UsageOrderSource {
    var config: AnyRouterConfig = .standard
    var session: URLSession = .shared

    private struct Response: Decodable {
        struct Item: Decodable { var id: String }
        var data: [Item]
    }

    func fetchUsageOrder() async throws -> [String] {
        var components = URLComponents(url: config.baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sort", value: "usage")]
        var request = URLRequest(url: components.url!)
        request.setValue(config.clientName, forHTTPHeaderField: "X-AnyRouter-Title")
        let (data, response) = try await session.data(for: request)
        let status = AnyRouterError.status(of: response)
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
    }
}
