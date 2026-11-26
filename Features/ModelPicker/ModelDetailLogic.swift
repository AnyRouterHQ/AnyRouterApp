import Foundation

/// What a model's detail screen lists, mapped from the catalog data. Pure, so it is tested without a view.
struct ModelDetail: Equatable {
    struct Field: Equatable, Identifiable {
        var label: String
        var value: String

        var id: String { label }
    }

    var wireID: String
    var description: String?
    var overview: [Field]
    var pricing: [Field]
    var capabilities: [RowCapability]
    var upstreams: [String]
    /// The last 7 days. Empty when the model had no traffic.
    var usage: [Field]
    /// The model's page on the AnyRouter site, and the catalog entry as JSON.
    var pageURL: URL
    var apiURL: URL
}

enum ModelDetailLogic {
    static func make(_ model: ModelDescriptor, usage: ModelUsage?, config: AnyRouterConfig = .standard) -> ModelDetail {
        let wire = model.wireID
        return ModelDetail(
            wireID: wire,
            description: nonEmpty(model.summary),
            overview: overview(model, wire: wire),
            pricing: pricing(model.cloud?.pricing),
            capabilities: RowCapability.of(model),
            upstreams: model.cloud?.upstreamNames ?? [],
            usage: usage.map(usageFields) ?? [],
            pageURL: config.origin.appending(path: "model/\(wire)"),
            apiURL: config.baseURL.appending(path: "models/\(wire)"))
    }

    private static func overview(_ model: ModelDescriptor, wire: String) -> [ModelDetail.Field] {
        var fields = [ModelDetail.Field(label: "ID", value: wire)]
        if let provider = nonEmpty(model.cloud?.providerName) ?? model.cloudProvider {
            fields.append(.init(label: "Provider", value: provider))
        }
        if let tokens = model.contextLength {
            fields.append(.init(label: "Context window", value: "\(PriceFormat.grouped(tokens)) tokens"))
        }
        if let tokens = model.cloud?.maxOutputTokens {
            fields.append(.init(label: "Max output", value: "\(PriceFormat.grouped(tokens)) tokens"))
        }
        if let members = model.cloud?.memberCount, members > 0, model.isRouter {
            fields.append(.init(label: "Routes to", value: "\(members) models"))
        }
        if let created = model.cloud?.created {
            fields.append(.init(label: "Released", value: releaseDate(created)))
        }
        if let cutoff = nonEmpty(model.cloud?.knowledgeCutoff) {
            fields.append(.init(label: "Knowledge cutoff", value: cutoff))
        }
        return fields
    }

    /// A free model has one line. Otherwise how it is billed, then the price of input, output and cached input.
    private static func pricing(_ pricing: CloudPricing?) -> [ModelDetail.Field] {
        guard let pricing else { return [] }
        if pricing.isFree { return [.init(label: "Price", value: "Free")] }
        var fields: [ModelDetail.Field] = []
        switch pricing.billing {
        case .credits: fields.append(.init(label: "Billing", value: "AnyRouter credits"))
        case .byok: fields.append(.init(label: "Billing", value: "Your provider key"))
        case .free, .unknown: break
        }
        for (label, price) in [("Input", pricing.input), ("Output", pricing.output), ("Cached input", pricing.cacheRead)] {
            if let price { fields.append(.init(label: label, value: "\(PriceFormat.amount(price)) per 1M tokens")) }
        }
        return fields
    }

    private static func usageFields(_ usage: ModelUsage) -> [ModelDetail.Field] {
        [
            .init(label: "Rank", value: "#\(usage.rank)"),
            .init(label: "Tokens", value: PriceFormat.compactCount(usage.tokens)),
            .init(label: "Requests", value: PriceFormat.compactCount(usage.requests)),
        ]
    }

    private static func releaseDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"), timeZone: .gmt))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
