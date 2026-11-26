import Foundation

/// `GET /api/v1/models`
struct ModelsResponse: Decodable {
    struct Item: Decodable {
        var id: String
        var name: String?
        var category: String?
        var contextLength: Int?
        var capabilities: [String]?
        var supportedParameters: [String]?
        var architecture: Architecture?

        struct Architecture: Decodable {
            var outputModalities: [String]?

            enum CodingKeys: String, CodingKey { case outputModalities = "output_modalities" }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, category, capabilities, architecture
            case contextLength = "context_length"
            case supportedParameters = "supported_parameters"
        }

        var kind: ModelKind {
            ModelKind.classify(
                category: category,
                outputModalities: architecture?.outputModalities ?? [],
                capabilities: capabilities ?? [],
                supportedParameters: supportedParameters ?? [])
        }
    }

    var data: [Item]

    /// Chat models only: embedding, rerank and decision models never reach the chat picker.
    /// `isInstalled` means usable now, so it follows the sign-in state.
    func descriptors(usable: Bool) -> [ModelDescriptor] {
        data
            .filter { $0.kind == .chat }
            .map { item in
                ModelDescriptor(
                    id: "anyrouter/\(item.id)",
                    source: .anyrouter,
                    displayName: item.name ?? item.id,
                    contextLength: item.contextLength,
                    capabilities: Self.normalized(item.capabilities ?? ["chat"]),
                    sizeBytes: nil,
                    isInstalled: usable
                )
            }
    }

    /// Decision models, for the Decisions screen. Ids are the wire ids (`anyrouter/decision`).
    func decisionModels() -> [DecisionModel] {
        data.filter { $0.kind == .decision }.map { DecisionModel(id: $0.id, name: $0.name ?? $0.id) }
    }

    /// The catalog tags tool support as `function-calling`; the app asks for `tools`.
    static func normalized(_ tags: [String]) -> Set<String> {
        var set = Set(tags)
        if !set.isDisjoint(with: ["function-calling", "function_calling", "tool-use", "tool_use"]) { set.insert("tools") }
        return set
    }
}
