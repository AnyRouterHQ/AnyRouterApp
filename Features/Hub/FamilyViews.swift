import SwiftUI

/// The second hop: a family's description and its sizes, with the best size for this device marked.
struct FamilyDetailView: View {
    let family: LocalModelFamily
    let filter: FamilyFilter

    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var prompts = LocalModelPrompts()
    @State private var detail: LocalModelEntry?

    private var device: String { DeviceName.current }
    private var variants: [LocalModelEntry] { FamilyLogic.variants(of: family, filter: filter) }
    private var recommendedID: String? { FamilyLogic.recommendedVariantID(in: family) }
    private var actions: LocalModelActions {
        LocalModelActions(hub: app.hub, models: models, memory: app.memory, prompts: prompts, device: device)
    }
    private var brand: ModelBrand {
        family.variants.first.map { ModelBrand.resolve($0.descriptor) } ?? .unknown
    }

    var body: some View {
        List {
            Section {
                ModelLabel(name: family.name, brand: brand)
                Text(family.summary)
                if !family.publisher.isEmpty { LabeledContent("Publisher", value: family.publisher) }
                if let site = family.website.flatMap(URL.init(string:)) {
                    Link("Website", destination: site)
                }
                if !family.tags.isEmpty {
                    LabeledContent("Capabilities", value: family.tags.map(\.capitalized).joined(separator: ", "))
                }
            }
            Section {
                // One row per size with Get at its end, so a size downloads from here; the row opens its page.
                ForEach(variants) { entry in
                    let state = app.hub.downloadState(for: entry.id)
                    HStack(spacing: 8) {
                        Button { detail = entry } label: {
                            ModelRow(entry: entry, state: state,
                                     note: entry.id == recommendedID ? "Recommended for this \(device)" : nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        ModelGetAccessory(entry: entry, state: state) { actions.requestDownload(entry) }
                    }
                    .swipeActions(edge: .trailing) { actions.swipe(entry, state: state) }
                    .contextMenu { actions.menu(entry, state: state) }
                }
            } header: {
                Text("Sizes")
            } footer: {
                if variants.count < family.variants.count {
                    Text("Showing the sizes that match your filters. Change them in Browse models to see all \(family.variants.count).")
                }
            }
        }
        .navigationTitle(family.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detail) { ModelDetailView(entry: $0) }
        .modifier(LocalModelDialogs(prompts: prompts, hub: app.hub, device: device))
        .overlay {
            if variants.isEmpty {
                ContentUnavailableView("No size matches", systemImage: "cube",
                                       description: Text("Change the filters in Browse models to see every size."))
            }
        }
    }
}
