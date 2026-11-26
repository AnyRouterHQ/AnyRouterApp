import Foundation

/// Reads the signed-in user's profile and spend. Each call is best effort: a failed one only drops its fields.
struct AccountSummaryLoader: Sendable {
    /// Returns the body and HTTP status.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    var baseURL: URL = AnyRouterConfig.standard.baseURL
    var fetch: Fetch = AccountSummaryLoader.urlSessionFetch

    /// Nil when no endpoint answered with data.
    func load(token: String) async -> AccountSummary? {
        async let me = body("me", token: token)
        async let credits = body("credits", token: token)
        let (meData, creditsData) = await (me, credits)
        // The sign-in token may not be allowed to read credits; this key's own usage is the fallback.
        let keyData = creditsData == nil ? await body("key", token: token) : nil
        let summary = AccountSummary.parse(me: meData, credits: creditsData, key: keyData)
        return summary.isEmpty ? nil : summary
    }

    func request(_ path: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func body(_ path: String, token: String) async -> Data? {
        guard let (data, status) = try? await fetch(request(path, token: token)), (200..<300).contains(status) else { return nil }
        return data
    }

    @Sendable
    static func urlSessionFetch(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
