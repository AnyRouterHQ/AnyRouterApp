import Foundation

/// One model a router can send a message to, in failover order.
struct RoutingMember: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var provider: String?
    var inputPer1M: Decimal?
    var outputPer1M: Decimal?
    var contextLength: Int?
}

/// Where the members of a router come from. AnyRouter's adapter calls `routing-preview`.
protocol RoutingPreviewSource: Sendable {
    /// `wireID` is the router's id, for example `anyrouter/auto`.
    func members(of wireID: String) async throws -> [RoutingMember]
}

/// `GET /api/v1/models/<router>/routing-preview`: the live failover chain. Public, no key needed.
struct AnyRouterRoutingPreview: RoutingPreviewSource {
    var config: AnyRouterConfig = .standard
    var session: URLSession = .shared

    struct Response: Decodable {
        struct Item: Decodable {
            var id: String
            var name: String?
            var provider: String?
            var contextLength: Int?
            var inputPer1M: ModelsResponse.Amount?
            var outputPer1M: ModelsResponse.Amount?

            enum CodingKeys: String, CodingKey {
                case id, name, provider
                case contextLength = "context_length"
                case inputPer1M = "input_price_per_1m"
                case outputPer1M = "output_price_per_1m"
            }
        }

        var resolved: [Item]

        var members: [RoutingMember] {
            resolved.map {
                RoutingMember(
                    id: $0.id, name: $0.name ?? $0.id, provider: $0.provider, inputPer1M: $0.inputPer1M?.value,
                    outputPer1M: $0.outputPer1M?.value, contextLength: $0.contextLength)
            }
        }
    }

    func members(of wireID: String) async throws -> [RoutingMember] {
        var request = URLRequest(url: config.baseURL.appending(path: "models/\(wireID)/routing-preview"))
        request.setValue(config.clientName, forHTTPHeaderField: "X-AnyRouter-Title")
        let (data, response) = try await session.data(for: request)
        let status = AnyRouterError.status(of: response)
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        return try JSONDecoder().decode(Response.self, from: data).members
    }
}
