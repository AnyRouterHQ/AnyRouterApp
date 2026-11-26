import SwiftUI

/// Settings › Local Models: what runs on this device. The system model, the sizes worth getting here, what is installed,
/// where the list comes from, and what it all costs in storage. A stock inset-grouped list.
/// The caller supplies the navigation stack (Settings and the hub sheet both do).
struct LocalModelsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var prompts = LocalModelPrompts()
    @State private var freeBytes: Int64?
    @State private var detail: LocalModelEntry?
    @State private var confirmsDeleteAll = false

    private var hub: any ModelHubService { app.hub }
    private var device: String { DeviceName.current }
    private var actions: LocalModelActions {
        LocalModelActions(hub: hub, models: models, memory: app.memory, prompts: prompts, device: device)
    }

        private var apple: ModelDescriptor? { models.models.first { $0.source == .apple } }
    private var installed: [LocalModelEntry] { LocalModelsLogic.installed(hub.catalog, state: { hub.downloadState(for: $0) }) }
    private var featured: [LocalModelEntry] { LocalModelsLogic.featured(families: hub.families, state: { hub.downloadState(for: $0) }) }
    private var downloading: [LocalModelEntry] {
        let shown = Set(featured.map(\.id))
        return hub.catalog.filter { hub.downloadState(for: $0.id).isActive && !shown.contains($0.id) }
    }
    private var unavailable: [LocalModelsLogic.UnavailableModel] {
        LocalModelsLogic.unavailable(catalog: hub.catalog, state: { hub.downloadState(for: $0) }, device: device)
    }
    private var storage: LocalModelsLogic.Storage { LocalModelsLogic.storage(installed: installed, freeBytes: freeBytes) }
    private var sourceCount: Int {
        CatalogSourcesLogic.sources(
            catalog: hub.catalog, remoteURL: hub.remoteCatalogURL, usesDevelopmentCatalog: hub.usesDevelopmentCatalog).count
    }

    var body: some View {
        List {
            if let note = models.defaultNote {
                Section { Label(note, systemImage: "exclamationmark.triangle") }
            }
            if let error = hub.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            systemSection
            featuredSection
            if !downloading.isEmpty {
                Section("Downloading") { ForEach(downloading) { installedRow($0) } }
            }
            if !installed.isEmpty {
                Section("Installed") { ForEach(installed) { installedRow($0) } }
                    .accessibilityIdentifier("local.installed")
            }
            Section("Sources") {
                NavigationLink {
                    CatalogSourcesScreen()
                } label: {
                    LabeledContent("Catalog Sources", value: "\(sourceCount)")
                }
            }
            storageSection
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("local.list")
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detail) { ModelDetailView(entry: $0) }
        .refreshable { await hub.refreshCatalog() }
        .modifier(LocalModelDialogs(prompts: prompts, hub: hub, device: device))
        .confirmationDialog("Delete all models?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete All Models", role: .destructive) { Task { await hub.deleteAllModels() } }
        } message: {
            Text(LocalModelsLogic.deleteAllMessage(storage, device: device))
        }
        .onChange(of: installed.map(\.id)) { Task { await models.refresh() } }
        .task {
            await app.memory.refresh()
            freeBytes = HubScreen.freeDiskBytes()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var systemSection: some View {
        if let apple {
            Section("System") {
                NavigationLink {
                    AppleModelScreen(model: apple)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            ModelLabel(model: apple)
                            Text(LocalModelsLogic.appleStatus(apple)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if models.selected?.id == apple.id {
                            Spacer()
                            DefaultBadge()
                        }
                    }
                }
                .accessibilityIdentifier("local.apple")
            }
        }
    }

    private var featuredSection: some View {
        Section("Featured") {
            ForEach(featured) { entry in
                let state = hub.downloadState(for: entry.id)
                HStack(spacing: 8) {
                    Button { detail = entry } label: {
                        ModelRow(entry: entry, state: state).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    accessory(entry, state: state)
                }
                .swipeActions(edge: .trailing) { actions.swipe(entry, state: state) }
                .contextMenu { actions.menu(entry, state: state) }
            }
            NavigationLink {
                HubScreen()
            } label: {
                Label("Browse all models", systemImage: "square.stack.3d.up")
            }
            .accessibilityIdentifier("local.browse")
            if !unavailable.isEmpty {
                NavigationLink {
                    UnavailableModelsScreen()
                } label: {
                    Text(LocalModelsLogic.unavailableTitle(count: unavailable.count, device: device))
                }
                .accessibilityIdentifier("local.unavailable")
            }
        }
        .accessibilityIdentifier("local.featured")
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Models", value: FitFormat.gigabytes(storage.usedBytes))
                .accessibilityIdentifier("local.storage")
            if let free = storage.freeBytes {
                LabeledContent("Free on device", value: FitFormat.gigabytes(free))
            }
            Button("Delete All Models", role: .destructive) { confirmsDeleteAll = true }
                .disabled(installed.isEmpty)
                .accessibilityIdentifier("local.deleteAll")
        } header: {
            Text("Storage")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let note = hub.memoryLimitNote { Text(note) }
                Text(LocalModelsLogic.disclaimer)
            }
        }
    }

    // MARK: Rows

    /// What stands at the end of a Featured row: Get, or a check once installed. A download in flight shows its own bar.
    @ViewBuilder
    private func accessory(_ entry: LocalModelEntry, state: DownloadState) -> some View {
        switch state {
        case .notInstalled, .failed:
            if entry.unavailableReason == nil {
                Button { actions.requestDownload(entry) } label: {
                    Text("Get").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Get \(entry.descriptor.displayName)")
            }
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Installed")
        case .downloading, .paused, .verifying:
            EmptyView()
        }
    }

    private func installedRow(_ entry: LocalModelEntry) -> some View {
        let state = hub.downloadState(for: entry.id)
        return NavigationLink {
            ModelDetailView(entry: entry)
        } label: {
            ModelRow(entry: entry, state: state, isDefault: models.selected?.id == entry.id && state == .installed)
        }
        .swipeActions(edge: .trailing) { actions.swipe(entry, state: state) }
        .contextMenu { actions.menu(entry, state: state) }
    }
}

/// The word that marks the default model. The star stays for favorites.
struct DefaultBadge: View {
    var body: some View {
        Text("Default").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Default model")
    }
}
