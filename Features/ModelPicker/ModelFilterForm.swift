import SwiftUI

/// Filters of the current tab, as a stock form pushed in the list's own navigation (a sheet on the picker sheet was a
/// sheet on a sheet, HIG audit 2026-11-28 #16). Changes apply at once; they are saved per tab.
struct ModelFilterForm: View {
    let tab: PickerTab
    @Binding var cloud: ModelFilter
    @Binding var local: LocalFilter
    let providers: [(name: String, count: Int)]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            switch tab {
            case .anyrouter: cloudSections
            case .local: localSections
            }
            Section {
                Button("Clear filters", role: .destructive) {
                    cloud = ModelFilter()
                    local = LocalFilter()
                }
                .disabled(!(tab == .local ? local.isActive : cloud.isActive))
                .accessibilityIdentifier("filters-clear")
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        // Done goes back to the list, like the back button.
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder
    private var cloudSections: some View {
        Section("Show") {
            Toggle("Free only", isOn: $cloud.freeOnly).accessibilityIdentifier("filter-free-only")
            Toggle("Hide models that need your key", isOn: $cloud.hideNeedsKey)
        }
        Section("Capabilities") {
            Toggle("Vision", isOn: $cloud.vision)
            Toggle("Tools", isOn: $cloud.tools)
            Toggle("Reasoning", isOn: $cloud.reasoning)
            Toggle("Long context (128K or more)", isOn: $cloud.longContext)
        }
        Section("Price") {
            Picker("Max input price per 1M", selection: $cloud.maxInputPrice) {
                ForEach(ModelFilter.MaxPrice.allCases) { Text($0.title).tag($0) }
            }
        }
        Section("Provider") {
            NavigationLink {
                ProviderFilterList(providers: providers, selection: $cloud.providers)
            } label: {
                LabeledContent("Providers", value: cloud.providers.isEmpty ? "All" : "\(cloud.providers.count) selected")
            }
        }
    }

    @ViewBuilder
    private var localSections: some View {
        Section("Model") {
            Picker("Engine", selection: $local.engine) {
                ForEach(LocalFilter.Engine.allCases) { Text($0.title).tag($0) }
            }
        }
        Section {
            Toggle("Fits this device", isOn: $local.fitsOnly)
            Toggle("Hide unavailable", isOn: $local.hideUnavailable)
        }
    }
}

/// Pick any number of providers.
private struct ProviderFilterList: View {
    let providers: [(name: String, count: Int)]
    @Binding var selection: Set<String>

    var body: some View {
        List(providers, id: \.name) { provider in
            Toggle(isOn: Binding(
                get: { selection.contains(provider.name) },
                set: { isOn in
                    if isOn { selection.insert(provider.name) } else { selection.remove(provider.name) }
                }
            )) {
                LabeledContent(ModelPickerLogic.providerTitle(provider.name), value: "\(provider.count)")
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
