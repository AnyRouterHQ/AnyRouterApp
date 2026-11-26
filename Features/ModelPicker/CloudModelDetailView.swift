import SwiftUI

/// Everything AnyRouter says about one model. Pushed from the info button of a picker row.
struct CloudModelDetailView: View {
    let model: ModelDescriptor
    let usage: ModelUsage?
    /// Set for a router: opens the list of models it picks from.
    var onShowRouting: (() -> Void)?

    var body: some View {
        let detail = ModelDetailLogic.make(model, usage: usage)
        Form {
            Section {
                ModelLabel(model: model, style: .row)
                if let description = detail.description { Text(description) }
            }
            Section("Overview") {
                ForEach(detail.overview) { field in
                    LabeledContent(field.label, value: field.value)
                }
                if let onShowRouting {
                    Button("Models it routes to", action: onShowRouting)
                }
            }
            if !detail.pricing.isEmpty {
                Section("Pricing") {
                    ForEach(detail.pricing) { field in
                        LabeledContent(field.label, value: field.value)
                    }
                }
            }
            if !detail.capabilities.isEmpty {
                Section("Capabilities") {
                    ForEach(detail.capabilities) { capability in
                        Label(capability.title, systemImage: capability.symbol)
                    }
                }
            }
            if !detail.usage.isEmpty {
                Section {
                    ForEach(detail.usage) { field in
                        LabeledContent(field.label, value: field.value)
                    }
                } header: {
                    Text("Last 7 days")
                } footer: {
                    Text("Public AnyRouter usage, ranked by tokens.")
                }
            }
            if !detail.upstreams.isEmpty {
                Section("Upstream providers") {
                    ForEach(Array(detail.upstreams.enumerated()), id: \.offset) { Text($0.element) }
                }
            }
            Section("Links") {
                Link(destination: detail.pageURL) { Label("Model page", systemImage: "safari") }
                Link(destination: detail.apiURL) { Label("Catalog entry (JSON)", systemImage: "curlybraces") }
            }
        }
        .navigationTitle(model.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("model-detail")
    }
}
