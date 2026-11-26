import SwiftUI

/// The models a router (like AnyRouter) picks from, in failover order.
struct RouterDetailSheet: View {
    let router: ModelDescriptor
    var source: any RoutingPreviewSource = AnyRouterRoutingPreview()

    @Environment(\.dismiss) private var dismiss
    @State private var members: [RoutingMember] = []
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded, failed(String) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 2) {
                            ModelLabel(name: member.name, brand: ModelBrand.resolve(id: member.id), style: .row)
                            Text(RouterDetailLogic.detail(member)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("router-member.\(member.id)")
                    }
                } footer: {
                    Text(RouterDetailLogic.footer)
                }
            }
            .overlay {
                switch phase {
                case .loading: ProgressView()
                case .failed(let message): ContentUnavailableView("Could not load", systemImage: "wifi.slash", description: Text(message))
                case .loaded: if members.isEmpty { ContentUnavailableView("No models", systemImage: "cube") }
                }
            }
            .navigationTitle(router.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func load() async {
        do {
            members = try await source.members(of: router.wireID)
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

enum RouterDetailLogic {
    static let footer = "AnyRouter tries these in order and falls back to the next one if a model is busy or fails."

    /// "OpenAI · $0.2 / $1.2 per 1M · 1M ctx"
    static func detail(_ member: RoutingMember) -> String {
        var parts: [String] = []
        if let provider = member.provider { parts.append(provider) }
        let pricing = CloudPricing(input: member.inputPer1M, output: member.outputPer1M, cacheRead: nil, billing: .credits)
        if let price = PriceFormat.line(pricing) { parts.append(price) }
        if let tokens = member.contextLength { parts.append(PriceFormat.context(tokens)) }
        return parts.joined(separator: " · ")
    }
}
