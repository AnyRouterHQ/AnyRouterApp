import SwiftUI

/// Edits where Browse Models gets its list: user-added Hugging Face repos and an optional remote catalog URL.
struct CatalogSourcesSheet: View {
    @Environment(AppState.self) private var app

    @State private var repoText = ""
    @State private var format: ModelSource = .gguf
    @State private var remoteText = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isBusy = false

    private var hub: any ModelHubService { app.hub }
    private var userModels: [LocalModelEntry] { hub.catalog.filter(\.isUserAdded) }

    var body: some View {
        Form {
            if let message {
                Section {
                    Text(message).foregroundStyle(isError ? Color.red : Color.secondary)
                }
            }
            Section("Add a Hugging Face repo") {
                TextField("org/name or huggingface.co URL", text: $repoText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Format", selection: $format) {
                    Text("GGUF").tag(ModelSource.gguf)
                    Text("MLX").tag(ModelSource.mlx)
                }
                .pickerStyle(.segmented)
                Button(isBusy ? "Adding…" : "Add repo") { addRepo() }
                    .disabled(isBusy || SettingsLogic.parseRepo(repoText) == nil)
            }
            Section {
                TextField("Default: the AnyRouter catalog on GitHub", text: $remoteText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("Use the development catalog", isOn: Binding(
                    get: { hub.usesDevelopmentCatalog },
                    set: { on in Task { await hub.setUsesDevelopmentCatalog(on) } }))
                Button(isBusy ? "Saving…" : "Save") { saveRemote() }
                    .disabled(isBusy)
            } header: {
                Text("Catalog source")
            } footer: {
                Text("The list is fetched at launch and when you pull to refresh. Leave empty to use the AnyRouter catalog on GitHub. The built-in list is the offline fallback.")
            }
            Section("Your models") {
                if userModels.isEmpty {
                    Text("Nothing added yet.").foregroundStyle(.secondary)
                }
                ForEach(userModels) { entry in
                    ModelLabel(model: entry.descriptor, style: .row)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await hub.removeUserModel(modelID: entry.id) }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                }
            }
        }
        .onAppear { remoteText = hub.remoteCatalogURL }
    }

    private func addRepo() {
        guard let repo = SettingsLogic.parseRepo(repoText) else { return }
        isBusy = true
        Task {
            do {
                try await hub.addRepo(RepoHit(repo: repo, source: format, downloads: nil, likes: nil))
                await hub.reload()
                repoText = ""
                show("Added \(repo).", error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
            isBusy = false
        }
    }

    private func saveRemote() {
        isBusy = true
        Task {
            do {
                try await hub.setRemoteCatalogURL(remoteText)
                show("Catalog source saved.", error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
            isBusy = false
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
