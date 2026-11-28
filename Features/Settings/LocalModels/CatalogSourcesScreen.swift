import SwiftUI

/// Where Local Models gets its list: the shared catalog and the Hugging Face repos added by hand. Each source opens its own page.
struct CatalogSourcesScreen: View {
    @Environment(AppState.self) private var app

    @State private var repoText = ""
    @State private var format: ModelSource = .gguf
    @State private var message: String?
    @State private var isError = false
    @State private var isBusy = false

    private var hub: any ModelHubService { app.hub }
    private var sources: [LocalCatalogSource] {
        CatalogSourcesLogic.sources(
            catalog: hub.catalog, remoteURL: hub.remoteCatalogURL, usesDevelopmentCatalog: hub.usesDevelopmentCatalog)
    }

    var body: some View {
        Form {
            if let message {
                Section { Text(message).foregroundStyle(isError ? Color.red : Color.primary) }
            }
            Section("Sources") {
                ForEach(sources) { source in
                    NavigationLink {
                        CatalogSourceDetailScreen(sourceID: source.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                            Text(CatalogSourcesLogic.subtitle(source)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if CatalogSourcesLogic.canRemove(source, state: { hub.downloadState(for: $0) }) {
                            Button(role: .destructive) {
                                Task { await hub.removeUserModels(source.models.map(\.id)) }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
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
        }
        .navigationTitle("Catalog Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addRepo() {
        guard let repo = SettingsLogic.parseRepo(repoText) else { return }
        isBusy = true
        Task {
            do {
                try await hub.addRepo(RepoHit(repo: repo, source: format, downloads: nil, likes: nil))
                await hub.reload()
                repoText = ""
                message = "Added \(repo)."
                isError = false
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isBusy = false
        }
    }
}

/// One source: what it is and where it points, its models, and the settings that belong to it.
struct CatalogSourceDetailScreen: View {
    let sourceID: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var remoteText = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isBusy = false
    @State private var confirmsRemove = false

    private var hub: any ModelHubService { app.hub }
    private var source: LocalCatalogSource? {
        CatalogSourcesLogic.sources(
            catalog: hub.catalog, remoteURL: hub.remoteCatalogURL, usesDevelopmentCatalog: hub.usesDevelopmentCatalog)
            .first { $0.id == sourceID }
    }

    var body: some View {
        Group {
            if let source {
                form(source)
            } else {
                ContentUnavailableView("Source removed", systemImage: "tray")
            }
        }
        .navigationTitle(source?.title ?? "Source")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { remoteText = hub.remoteCatalogURL }
    }

    private func form(_ source: LocalCatalogSource) -> some View {
        Form {
            if let message {
                Section { Text(message).foregroundStyle(isError ? Color.red : Color.primary) }
            }
            Section {
                LabeledContent("Type", value: source.typeName)
                LabeledContent("Address") { Text(source.address).textSelection(.enabled) }
                if let format = source.format { LabeledContent("Format", value: format) }
                if source.kind == .huggingFaceRepo { LabeledContent("Revision", value: source.revision ?? "main") }
                LabeledContent("Models", value: "\(source.models.count)")
            }
            if source.kind == .sharedCatalog { catalogSettings }
            Section("Models") {
                ForEach(source.models) { entry in
                    NavigationLink {
                        ModelDetailView(entry: entry)
                    } label: {
                        ModelLabel(model: entry.descriptor)
                    }
                }
            }
            if source.isRemovable { removeSection(source) }
        }
        .confirmationDialog("Remove \(source.title)?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove Source", role: .destructive) {
                Task {
                    await hub.removeUserModels(source.models.map(\.id))
                    dismiss()
                }
            }
        } message: {
            Text("Its models leave your list. You can add the repo again later.")
        }
    }

    @ViewBuilder
    private var catalogSettings: some View {
        Section {
            TextField("Default: the AnyRouter catalog on GitHub", text: $remoteText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Toggle("Use the development catalog", isOn: Binding(
                get: { hub.usesDevelopmentCatalog },
                set: { on in Task { await hub.setUsesDevelopmentCatalog(on) } }))
            .formSwitches()
            Button(isBusy ? "Saving…" : "Save") { saveRemote() }
                .disabled(isBusy)
        } header: {
            Text("Catalog address")
        } footer: {
            Text("The list is fetched at launch and when you pull to refresh. Leave empty to use the AnyRouter catalog on GitHub. The built-in list is the offline fallback.")
        }
    }

    private func removeSection(_ source: LocalCatalogSource) -> some View {
        let removable = CatalogSourcesLogic.canRemove(source, state: { hub.downloadState(for: $0) })
        return Section {
            Button("Remove Source", role: .destructive) { confirmsRemove = true }
                .disabled(!removable)
        } footer: {
            if !removable { Text("Delete its downloaded models in Local Models first.") }
        }
    }

    private func saveRemote() {
        isBusy = true
        Task {
            do {
                try await hub.setRemoteCatalogURL(remoteText)
                message = "Catalog address saved."
                isError = false
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isBusy = false
        }
    }
}
