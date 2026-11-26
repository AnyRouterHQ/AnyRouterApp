import Foundation

/// `GET /api/v1/models`
struct ModelsResponse: Decodable {
    struct Item: Decodable {
        var id: String
        var name: String?
        var category: String?
        var description: String?
        var contextLength: Int?
        var capabilities: [String]?
        var supportedParameters: [String]?
        var architecture: Architecture?
        var created: Double?
        var providers: [String]?
        var members: [Member]?
        var pricing: Pricing?
        var canRoute: Bool?
        var canRouteReason: String?
        var logo: String?
        var provider: LenientString?
        var knowledgeCutoff: LenientString?
        var topProvider: TopProvider?

        struct TopProvider: Decodable {
            var maxCompletionTokens: Amount?

            enum CodingKeys: String, CodingKey { case maxCompletionTokens = "max_completion_tokens" }
        }

        struct Architecture: Decodable {
            var inputModalities: [String]?
            var outputModalities: [String]?

            enum CodingKeys: String, CodingKey {
                case inputModalities = "input_modalities"
                case outputModalities = "output_modalities"
            }
        }

        /// Only the count of router members is used.
        struct Member: Decodable {}

        /// Prices are USD per 1M tokens. The catalog sends numbers and strings, so both parse.
        struct Pricing: Decodable {
            var prompt: Amount?
            var completion: Amount?
            var inputPer1M: Amount?
            var outputPer1M: Amount?
            var inputCacheReadPer1M: Amount?
            var billing: String?

            enum CodingKeys: String, CodingKey {
                case prompt, completion, billing
                case inputPer1M = "input_per_1m"
                case outputPer1M = "output_per_1m"
                case inputCacheReadPer1M = "input_cache_read_per_1m"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, category, description, capabilities, architecture, created, providers, members, pricing, logo, provider
            case contextLength = "context_length"
            case knowledgeCutoff = "knowledge_cutoff"
            case topProvider = "top_provider"
            case supportedParameters = "supported_parameters"
            case canRoute = "can_route"
            case canRouteReason = "can_route_reason"
        }

        var cloudInfo: CloudInfo { cloudInfo(signedIn: true) }

        /// `can_route` is worked out for the caller's key. Without a key it only says what an anonymous caller may use,
        /// so a signed-out list reads every routable model as usable: the sign-in sheet explains the rest.
        func cloudInfo(signedIn: Bool) -> CloudInfo {
            let input = pricing?.inputPer1M?.value ?? pricing?.prompt?.value
            let output = pricing?.outputPer1M?.value ?? pricing?.completion?.value
            let billing = CloudBilling(rawValue: pricing?.billing ?? "") ?? .unknown
            let availability: CloudAvailability
            switch (canRoute, canRouteReason) {
            case (false, "no_route"): availability = .noRoute
            case (false, "disabled"): availability = .disabled
            case (false, _): availability = signedIn ? .needsKey : .usable
            default: availability = .usable
            }
            let tags = Set(capabilities ?? [])
            let parameters = Set(supportedParameters ?? [])
            return CloudInfo(
                pricing: CloudPricing(
                    input: input, output: output,
                    cacheRead: pricing?.inputCacheReadPer1M?.value, billing: billing),
                availability: availability,
                upstreamCount: providers?.count,
                memberCount: members?.count,
                supportsVision: tags.contains("vision") || (architecture?.inputModalities ?? []).contains("image"),
                supportsReasoning: tags.contains("reasoning")
                    || !parameters.isDisjoint(with: ["reasoning", "reasoning_effort", "include_reasoning"]),
                created: created.map { Date(timeIntervalSince1970: $0) },
                logoURL: logo.flatMap(URL.init(string:)),
                providerName: provider?.value,
                knowledgeCutoff: knowledgeCutoff?.value,
                upstreamNames: providers,
                maxOutputTokens: topProvider?.maxCompletionTokens?.value.map { NSDecimalNumber(decimal: $0).intValue })
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
    /// Entries that could not be read and were left out. One odd entry never takes the whole catalog with it.
    var skipped = 0

    /// Chat models only: embedding, rerank and decision models never reach the chat picker.
    /// `isInstalled` means usable now, so it follows the sign-in state.
    func descriptors(usable: Bool) -> [ModelDescriptor] {
        data
            .filter { $0.kind == .chat }
            .map { item in
                let info = item.cloudInfo(signedIn: usable)
                return ModelDescriptor(
                    id: "anyrouter/\(item.id)",
                    source: .anyrouter,
                    displayName: item.name ?? item.id,
                    contextLength: item.contextLength,
                    capabilities: Self.normalized(
                        item.capabilities ?? ["chat"], supportedParameters: item.supportedParameters ?? [],
                        inputModalities: item.architecture?.inputModalities ?? []),
                    sizeBytes: nil,
                    isInstalled: usable && info.availability == .usable,
                    summary: item.description,
                    cloud: info
                )
            }
    }

    /// Decision models, for the Decisions screen. Ids are the wire ids (`anyrouter/decision`).
    func decisionModels() -> [DecisionModel] {
        data.filter { $0.kind == .decision }.map { DecisionModel(id: $0.id, name: $0.name ?? $0.id) }
    }

    /// Reads `data` entry by entry: an entry that does not read is counted and skipped.
    private enum CodingKeys: String, CodingKey { case data }

    /// Moves past an entry that failed to decode, which a failed `decode` does not do by itself.
    private struct Discarded: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var list = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .data)
        var items: [Item] = []
        var unreadable = 0
        while !list.isAtEnd {
            if let item = try? list.decode(Item.self) {
                items.append(item)
            } else {
                unreadable += 1
                _ = try? list.decode(Discarded.self)
            }
        }
        data = items
        skipped = unreadable
    }

    /// A string, or nil for any other shape, so a field that is only shown never breaks the whole list.
    struct LenientString: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    /// A number or a numeric string, as a Decimal.
    struct Amount: Decodable {
        let value: Decimal?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = Decimal(string: "\(number)")
            } else if let text = try? container.decode(String.self) {
                value = Decimal(string: text)
            } else {
                value = nil
            }
        }
    }

    /// The catalog tags tool support as `function-calling`; the app asks for `tools`.
    /// A model that lists `tools` among its supported request parameters can call tools too.
    /// A model whose input modalities include `image` can see photos.
    static func normalized(_ tags: [String], supportedParameters: [String] = [], inputModalities: [String] = []) -> Set<String> {
        var set = Set(tags)
        if inputModalities.contains("image") { set.insert("vision") }
        if !set.isDisjoint(with: ["function-calling", "function_calling", "tool-use", "tool_use"])
            || supportedParameters.contains("tools") {
            set.insert("tools")
        }
        return set
    }
}
