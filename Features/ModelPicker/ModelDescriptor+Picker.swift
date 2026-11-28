import Foundation

/// Picker-facing view of a model id. Cloud ids are `anyrouter/<provider>/<model>`.
extension ModelDescriptor {
    /// The router that picks a model per message. Shown as just "AnyRouter".
    static let autoRouterID = "anyrouter/anyrouter/auto"
    /// Needs the user's own provider keys, so it is not offered by default.
    static let byokRouterID = "anyrouter/anyrouter/byok"

    /// The id the API knows (`<provider>/<model>`) for cloud models, the plain id otherwise.
    var wireID: String {
        source == .anyrouter && id.hasPrefix("anyrouter/") ? String(id.dropFirst("anyrouter/".count)) : id
    }

    /// The part of the wire id before the first slash, for cloud models.
    var cloudProvider: String? {
        guard source == .anyrouter, let slash = wireID.firstIndex(of: "/") else { return nil }
        return String(wireID[..<slash])
    }

    /// AnyRouter's own routers: auto, coding, agent, ...
    var isRouter: Bool { cloudProvider == "anyrouter" }

    /// Name for the chat header, picker rows, reply footers and Local Models (`ModelShortLabel.name`).
    var shortName: String { ModelShortLabel.name(of: self) }
}
