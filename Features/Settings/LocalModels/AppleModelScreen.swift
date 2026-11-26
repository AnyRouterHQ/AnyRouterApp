import SwiftUI

/// The model built into the system. It has no download and no settings of its own: the generation settings people
/// already use apply to it, so Advanced links to them.
struct AppleModelScreen: View {
    let model: ModelDescriptor

    @Environment(ModelStore.self) private var models

    var body: some View {
        List {
            Section {
                ModelLabel(model: model)
                Text(LocalModelsLogic.appleStatus(model)).foregroundStyle(.secondary)
            }
            Section {
                if models.selected?.id == model.id {
                    Label("Default model", systemImage: "star.fill")
                } else {
                    Button("Set as Default", systemImage: "star") { models.select(model) }
                        .disabled(!model.isInstalled)
                }
            }
            Section {
                NavigationLink {
                    ResponseCustomizationSettings()
                        .navigationTitle("Response Customization")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Sampling and length", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Temperature, top P, reply length and the system prompt apply to this model like every other.")
            }
        }
        .navigationTitle(model.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
