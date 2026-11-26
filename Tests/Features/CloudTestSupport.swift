import Foundation
@testable import AnyRouter

/// A cloud model as the picker sees it. `usable` is "signed in and routable".
func cloudModel(
    _ wire: String, name: String? = nil, input: Decimal? = 3, output: Decimal? = 15,
    billing: CloudBilling = .credits, availability: CloudAvailability = .usable, usable: Bool = true,
    upstreams: Int? = 5, members: Int? = nil, context: Int? = 128_000, created: TimeInterval? = nil,
    vision: Bool = false, reasoning: Bool = false, summary: String? = nil
) -> ModelDescriptor {
    ModelDescriptor(
        id: "anyrouter/\(wire)", source: .anyrouter, displayName: name ?? wire, contextLength: context,
        capabilities: ["chat"], sizeBytes: nil, isInstalled: usable && availability == .usable, summary: summary,
        cloud: CloudInfo(
            pricing: CloudPricing(input: input, output: output, cacheRead: nil, billing: billing),
            availability: availability, upstreamCount: upstreams, memberCount: members,
            supportsVision: vision, supportsReasoning: reasoning,
            created: created.map { Date(timeIntervalSince1970: $0) }, logoURL: nil))
}

func localModel(
    _ id: String, name: String? = nil, source: ModelSource = .gguf, size: Int64? = 1_050_000_000, installed: Bool = true
) -> ModelDescriptor {
    ModelDescriptor(
        id: id, source: source, displayName: name ?? id, contextLength: nil, capabilities: ["chat"],
        sizeBytes: size, isInstalled: installed)
}
