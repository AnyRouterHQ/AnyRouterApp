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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let message {
                        if isError { ErrorBanner(text: message) { self.message = nil } }
                        else { SettingsText(message) }
                    }
                    SettingsGroup("Add a Hugging Face repo") {
                        TextField("org/name or huggingface.co URL", text: $repoText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
                        Picker("Format", selection: $format) {
                            Text("GGUF").tag(ModelSource.gguf)
                            Text("MLX").tag(ModelSource.mlx)
                        }
                        .pickerStyle(.segmented)
                        Button(isBusy ? "Adding…" : "Add repo") { addRepo() }
                            .buttonStyle(.arFilled)
                            .disabled(isBusy || SettingsLogic.parseRepo(repoText) == nil)
                    }
                    SettingsGroup("Catalog source") {
                        TextField("Default: the AnyRouter catalog on GitHub", text: $remoteText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(10)
                            .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
                        SettingsText("The list is fetched at launch and when you pull to refresh. Leave empty to use the AnyRouter catalog on GitHub. The built-in list is the offline fallback.")
                        Toggle("Use the development catalog", isOn: Binding(
                            get: { hub.usesDevelopmentCatalog },
                            set: { on in Task { await hub.setUsesDevelopmentCatalog(on) } }))
                            .font(.arBase)
                            .tint(ARColor.accent)
                        Button(isBusy ? "Saving…" : "Save") { saveRemote() }
                            .buttonStyle(.arSecondary)
                            .disabled(isBusy)
                    }
                    SettingsGroup("Your models") {
                        if userModels.isEmpty {
                            SettingsText("Nothing added yet.")
                        }
                        ForEach(userModels) { entry in
                            HStack {
                                Text(entry.descriptor.displayName).font(.arBase).foregroundStyle(ARColor.foreground).lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await hub.removeUserModel(modelID: entry.id) }
                                } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Remove \(entry.descriptor.displayName)")
                            }
                        }
                    }
                }
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
            }
        }
        .background(ARColor.background.ignoresSafeArea())
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
