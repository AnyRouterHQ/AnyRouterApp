import SwiftUI

/// The catalog sizes this device cannot run, each with the reason in plain words. The list follows the device:
/// an iPad with more memory has a shorter one.
struct UnavailableModelsScreen: View {
    @Environment(AppState.self) private var app

    private var device: String { DeviceName.current }

    private var items: [LocalModelsLogic.UnavailableModel] {
        LocalModelsLogic.unavailable(catalog: app.hub.catalog, state: { app.hub.downloadState(for: $0) }, device: device)
    }

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink {
                        ModelDetailView(entry: item.entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ModelLabel(model: item.entry.descriptor)
                            Text(LocalModelsLogic.fileLine(item.entry)).font(.subheadline).foregroundStyle(.secondary)
                            Text(item.reason).font(.subheadline)
                        }
                    }
                }
            } footer: {
                if !items.isEmpty {
                    Text("These sizes need more memory than iOS gives an app on this \(device).")
                }
            }
        }
        .accessibilityIdentifier("local.unavailable.list")
        .navigationTitle("Not Available")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Everything fits", systemImage: "checkmark.circle",
                    description: Text("Every model in the catalog can run on this \(device)."))
            }
        }
    }
}
