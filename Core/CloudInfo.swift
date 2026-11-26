import Foundation

/// How a cloud model is billed. `byok` means the user pays the provider with their own key.
enum CloudBilling: String, Codable, Sendable { case free, credits, byok, unknown }

/// Whether this user can send a request to a cloud model right now.
enum CloudAvailability: String, Codable, Sendable { case usable, needsKey, noRoute, disabled }

/// Prices in USD per 1M tokens. `nil` means the catalog did not say.
struct CloudPricing: Hashable, Codable, Sendable {
    var input: Decimal?
    var output: Decimal?
    var cacheRead: Decimal?
    var billing: CloudBilling

    var isFree: Bool {
        billing == .free || (input == 0 && output == 0)
    }
}

/// What AnyRouter says about one cloud model, parsed once at the API boundary.
struct CloudInfo: Hashable, Codable, Sendable {
    var pricing: CloudPricing
    var availability: CloudAvailability
    /// Upstream providers that can serve it (normal models).
    var upstreamCount: Int?
    /// Models a router picks from (`anyrouter/*` routers).
    var memberCount: Int?
    var supportsVision: Bool
    var supportsReasoning: Bool
    var created: Date?
    /// Logo from the API when it has one. The bundled set is the fallback.
    var logoURL: URL?
}
