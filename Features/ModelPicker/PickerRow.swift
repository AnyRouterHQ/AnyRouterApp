import Foundation

/// What one picker row shows. Two text lines, so the list keeps a fixed row height.
struct ModelRowModel: Equatable, Identifiable {
    var id: String
    /// Line 1, never truncated before the id.
    var title: String
    /// Line 1, muted. Truncated in the middle when long.
    var idLabel: String
    /// Line 2, muted, joined with " · ".
    var details: [String]
    var brand: ModelBrand
    /// Cloud model this user cannot use now. The row is dimmed and explains why.
    var isDimmed: Bool
    var needsKey: Bool
    /// The model takes images, so the row shows an eye.
    var supportsVision = false

    var detailLine: String { details.joined(separator: " · ") }
}

enum PickerRow {
    static let needsKeyText = "Needs your provider key"
    static let unavailableText = "Unavailable"
    static let idLimit = 34

    /// `fitBadge` is the device-fit text for a local model, when the hub has numbers for it.
    static func make(_ model: ModelDescriptor, fitBadge: String? = nil) -> ModelRowModel {
        switch model.source {
        case .apple:
            var details = ["On device · Free"]
            if !model.isInstalled { details.append(model.summary ?? "Not available on this device") }
            return ModelRowModel(
                id: model.id, title: model.shortName, idLabel: model.id, details: details,
                brand: ModelBrand.resolve(model), isDimmed: !model.isInstalled, needsKey: false)
        case .gguf, .mlx:
            var details = ["On device · Free"]
            if let size = model.sizeBytes { details.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            details.append(format(model))
            if let fitBadge { details.append(fitBadge) }
            let repo = model.id.split(separator: "/").dropFirst().joined(separator: "/")
            return ModelRowModel(
                id: model.id, title: model.displayName, idLabel: middleTruncated(repo), details: details,
                brand: ModelBrand.resolve(model), isDimmed: false, needsKey: false)
        case .anyrouter:
            return cloud(model)
        }
    }

    private static func cloud(_ model: ModelDescriptor) -> ModelRowModel {
        let info = model.cloud
        var details: [String] = []
        switch info?.availability {
        case .needsKey: details.append(needsKeyText)
        case .noRoute, .disabled: details.append(unavailableText)
        default:
            if let info, let price = PriceFormat.line(info.pricing) { details.append(price) }
        }
        if let tokens = model.contextLength { details.append(PriceFormat.context(tokens)) }
        if let members = info?.memberCount, members > 0, model.isRouter {
            details.append("routes \(members) models")
        } else if let upstreams = info?.upstreamCount, upstreams > 0 {
            details.append(upstreams == 1 ? "1 upstream" : "\(upstreams) upstreams")
        }
        if info?.supportsVision == true { details.append("vision") }
        if info?.supportsReasoning == true { details.append("reasoning") }
        let availability = info?.availability ?? .usable
        return ModelRowModel(
            id: model.id, title: model.shortName, idLabel: middleTruncated(model.wireID), details: details,
            brand: ModelBrand.resolve(model), isDimmed: availability != .usable && !model.isInstalled,
            needsKey: availability == .needsKey, supportsVision: model.supportsVision)
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
