import SwiftUI

/// One family in the Available list: logo and name, who made it, how many sizes fit, tags.
struct FamilyRow: View {
    let family: LocalModelFamily

    private var brand: ModelBrand {
        family.variants.first.map { ModelBrand.resolve($0.descriptor) } ?? .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModelLabel(name: family.name, brand: brand)
            Text([family.publisher, FamilyLogic.fitSummary(family, device: DeviceName.current)]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            let extras = family.badges.map(\.capitalized) + family.tags.map(\.capitalized)
            if !extras.isEmpty {
                Text(extras.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The second hop: a family's description and its sizes, with the best size for this device marked.
struct FamilyDetailView: View {
    let family: LocalModelFamily
    let filter: FamilyFilter

    @Environment(AppState.self) private var app

    private var device: String { DeviceName.current }
    private var variants: [LocalModelEntry] { FamilyLogic.variants(of: family, filter: filter) }
    private var recommendedID: String? { FamilyLogic.recommendedVariantID(in: family) }
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
                ForEach(variants) { entry in
                    NavigationLink {
                        ModelDetailView(entry: entry)
                    } label: {
                        ModelRow(
                            entry: entry,
                            state: app.hub.downloadState(for: entry.id),
                            note: entry.id == recommendedID ? "Recommended for this \(device)" : nil
                        )
                    }
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
        .overlay {
            if variants.isEmpty {
                ContentUnavailableView("No size matches", systemImage: "cube",
                                       description: Text("Change the filters in Browse models to see every size."))
            }
        }
    }
}
