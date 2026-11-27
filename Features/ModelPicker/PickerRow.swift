import Foundation

/// What one picker row shows. Two text lines, so the list keeps a fixed row height.
struct ModelRowModel: Equatable, Identifiable {
    var id: String
    /// Line 1, never truncated before the id.
    var title: String
    /// Line 1, muted. Truncated in the middle when long. Empty for cloud models: their id is on the detail screen.
    var idLabel: String
    /// Line 2, muted, joined with " · ". When `isFree`, the first one is the "Free" badge.
    var details: [String]
    var brand: ModelBrand
    /// Cloud model this user cannot use now. The row is dimmed and explains why.
    var isDimmed: Bool
    var needsKey: Bool
    /// Shown as symbols at the end of line 2.
    var capabilities: [RowCapability] = []
    /// The first detail is the "Free" badge, not plain text.
    var isFree = false
    /// The model's last 7 days, when this list is ranked by them.
    var usage: ModelUsage? = nil

    var supportsVision: Bool { capabilities.contains(.vision) }

    var detailLine: String { details.joined(separator: " · ") }

    /// Line 2 after the badge, so the view can draw the badge itself.
    var detailsAfterBadge: String { details.dropFirst(isFree ? 1 : 0).joined(separator: " · ") }

    /// "#1" for the most used models. Further down the ranking a number says little.
    var rankText: String? {
        guard let usage, usage.rank <= PickerRow.rankedCount else { return nil }
        return "#\(usage.rank)"
    }
}

/// What a model can do, as a symbol on its row and a line on its detail screen.
enum RowCapability: String, CaseIterable, Identifiable, Sendable {
    case vision, reasoning, tools

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .vision: "eye"
        case .reasoning: "brain"
        case .tools: "wrench"
        }
    }

    var title: String {
        switch self {
        case .vision: "Sees images"
        case .reasoning: "Reasons step by step"
        case .tools: "Uses tools"
        }
    }

    /// In the order they are drawn.
    static func of(_ model: ModelDescriptor) -> [RowCapability] {
        allCases.filter { $0.isSupported(by: model) }
    }

    private func isSupported(by model: ModelDescriptor) -> Bool {
        switch self {
        case .vision: return model.supportsVision
        case .reasoning: return model.supportsThinking || model.cloud?.supportsReasoning == true
        case .tools: return model.capabilities.contains("tools")
        }
    }
}

enum PickerRow {
    static let needsKeyText = "Needs your provider key"
    static let unavailableText = "Unavailable"
    static let idLimit = 34
    /// Models up to this place in the weekly ranking show their number: the ten the short list shows.
    static let rankedCount = CloudListLogic.topCount

    /// `fitBadge` is the device-fit text for a local model, when the hub has numbers for it.
    /// `usage` is set only when the list is ranked by weekly usage (see `CloudListLogic.rowUsage`).
    static func make(_ model: ModelDescriptor, fitBadge: String? = nil, usage: ModelUsage? = nil) -> ModelRowModel {
        switch model.source {
        case .apple:
            var details = ["On device · Free"]
            if !model.isInstalled { details.append(model.summary ?? "Not available on this device") }
            return ModelRowModel(
                id: model.id, title: model.shortName, idLabel: model.id, details: details,
                brand: ModelBrand.resolve(model), isDimmed: !model.isInstalled, needsKey: false,
                capabilities: RowCapability.of(model))
        case .gguf, .mlx:
            var details = ["On device · Free"]
            if let size = model.sizeBytes { details.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            details.append(format(model))
            if let fitBadge { details.append(fitBadge) }
            let repo = model.id.split(separator: "/").dropFirst().joined(separator: "/")
            return ModelRowModel(
                id: model.id, title: model.displayName, idLabel: middleTruncated(repo), details: details,
                brand: ModelBrand.resolve(model), isDimmed: false, needsKey: false,
                capabilities: RowCapability.of(model))
        case .anyrouter:
            return cloud(model, usage: usage)
        }
    }

    /// Line 2 of a cloud row: price (or why it cannot be used), context, then a router's size.
    private static func cloud(_ model: ModelDescriptor, usage: ModelUsage?) -> ModelRowModel {
        let info = model.cloud
        var details: [String] = []
        var isFree = false
        switch info?.availability {
        case .needsKey: details.append(needsKeyText)
        case .noRoute, .disabled: details.append(unavailableText)
        default:
            if let info, let price = PriceFormat.line(info.pricing) {
                details.append(price)
                isFree = info.pricing.isFree
            }
        }
        if let tokens = model.contextLength { details.append(PriceFormat.context(tokens)) }
        if let members = info?.memberCount, members > 0, model.isRouter {
            details.append("routes \(members) models")
        }
        let availability = info?.availability ?? .usable
        return ModelRowModel(
            id: model.id, title: title(model), idLabel: "", details: details,
            brand: ModelBrand.resolve(model), isDimmed: availability != .usable && !model.isInstalled,
            needsKey: availability == .needsKey, capabilities: RowCapability.of(model), isFree: isFree, usage: usage)
    }

    /// AnyRouter's own presets go by their full id ("anyrouter/auto"), the way people type them in the API.
    static func title(_ model: ModelDescriptor) -> String {
        model.isRouter ? model.wireID : model.shortName
    }

    /// "GGUF Q4_K_M" or "MLX 4-bit".
    static func format(_ model: ModelDescriptor) -> String {
        let name = model.source == .gguf ? "GGUF" : "MLX"
        let text = model.id
        if model.source == .gguf,
           let range = text.range(
               of: "(?<![A-Za-z0-9])(IQ\\d(_[A-Z0-9]+)*|Q\\d(_[A-Z0-9]+)*|BF16|F16|F32)(?![A-Za-z0-9])",
               options: [.regularExpression, .caseInsensitive]) {
            return "\(name) \(text[range].uppercased())"
        }
        if model.source == .mlx,
           let range = text.range(of: "\\d+(?=-?bit)", options: [.regularExpression, .caseInsensitive]) {
            return "\(name) \(text[range])-bit"
        }
        return name
    }

    /// Keeps both ends of a long id: "anthropic/claude-sonn…-20260101".
    static func middleTruncated(_ text: String, limit: Int = idLimit) -> String {
        guard text.count > limit, limit > 8 else { return text }
        let head = (limit - 1) * 2 / 3
        let tail = limit - 1 - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }
}
