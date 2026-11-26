import Foundation

/// `GET /api/v1/models`
struct ModelsResponse: Decodable {
    struct Item: Decodable {
        var id: String
        var name: String?
        var category: String?
        var contextLength: Int?
        var capabilities: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, category, capabilities
            case contextLength = "context_length"
        }
    }

    var data: [Item]

    /// Chat models only. `isInstalled` means usable now, so it follows the sign-in state.
    func descriptors(usable: Bool) -> [ModelDescriptor] {
        data
            .filter { $0.category == nil || $0.category == "text" }
            .map { item in
                ModelDescriptor(
                    id: "anyrouter/\(item.id)",
                    source: .anyrouter,
                    displayName: item.name ?? item.id,
                    contextLength: item.contextLength,
                    capabilities: Set(item.capabilities ?? ["chat"]),
                    sizeBytes: nil,
                    isInstalled: usable
                )
            }
    }
}
