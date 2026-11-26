import SwiftUI

/// Sheet wrapper: Manage models in its own navigation stack with a close button.
struct HubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HubScreen()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                }
        }
    }
}

/// Manage models: what is on this device, what is downloading, and what can be added. A stock inset-grouped list.
/// The caller supplies the navigation stack (the hub sheet and Settings both do).
struct HubScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var query = ""
    @State private var sort = FamilySort.recommended
    @State private var filter = FamilyFilter()
    @State private var showsRepoSearch = false
    @State private var showsAddByLink = false
    @State private var freeBytes: Int64?
    @State private var pendingDelete: LocalModelEntry?
    @State private var pendingDownload: LocalModelEntry?

    private var hub: any ModelHubService { app.hub }
    private var device: String { DeviceName.current }

    private var sections: HubLogic.Sections {
        HubLogic.sections(catalog: hub.catalog, state: { hub.downloadState(for: $0) }, query: query)
    }

    /// Installed and downloading models always show: they are the person's own, whatever the filter says.
    private var installed: [LocalModelEntry] { sections.installed }

    private var downloading: [LocalModelEntry] {
        sections.available.filter { hub.downloadState(for: $0.id).isActive }
    }

    /// The short list of sizes that run well on this device, best first. Not shown while searching, and not for models
    /// that are already installed or downloading: those have their own sections.
    private var recommended: [LocalModelEntry] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return FamilyLogic.recommendedEntries(from: hub.families).filter { entry in
            let state = hub.downloadState(for: entry.id)
            return state != .installed && !state.isActive
        }
    }

    private var families: [LocalModelFamily] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? hub.families : hub.families.filter { HubListOptions.matches($0, needle) }
        return FamilyLogic.apply(matched, sort: sort, filter: filter)
    }

    /// Models that are in no family (added by the user or found on Hugging Face) and not on the device yet.
    private var ungrouped: [LocalModelEntry] {
        hub.ungroupedModels.filter { entry in
            !hub.downloadState(for: entry.id).isActive && hub.downloadState(for: entry.id) != .installed
                && filter.keeps(entry) && (query.isEmpty || HubLogic.matches(entry, query))
        }
    }

    private var appleModel: ModelDescriptor? {
        models.models.first { $0.source == .apple && $0.isInstalled }
    }

    private var showsApple: Bool {
        appleModel != nil && (query.isEmpty || "Apple Intelligence".localizedCaseInsensitiveContains(query))
            && (filter.engines.isEmpty || filter.engines.contains(.apple)) && filter.tags.isEmpty
    }

    private var installedIDs: [String] {
        hub.catalog.filter { hub.downloadState(for: $0.id) == .installed }.map(\.id)
    }

    private var usedBytes: Int64 {
        hub.catalog.filter { hub.downloadState(for: $0.id) == .installed }.reduce(0) { $0 + ($1.descriptor.sizeBytes ?? 0) }
    }

    private var isEmpty: Bool {
        installed.isEmpty && downloading.isEmpty && families.isEmpty && ungrouped.isEmpty && !showsApple
    }

    var body: some View {
        List {
            if let error = hub.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Storage", value: HubListOptions.storageSummary(usedBytes: usedBytes, freeBytes: freeBytes))
                    .accessibilityIdentifier("hub.storage")
            } footer: {
                if let note = hub.memoryLimitNote { Text(note) }
            }
            if !installed.isEmpty || showsApple {
                Section("On this \(device)") {
                    if showsApple, let appleModel { appleRow(appleModel) }
                    ForEach(installed) { entry in row(entry) }
                }
            }
            if !downloading.isEmpty {
                Section("Downloading") { ForEach(downloading) { entry in row(entry) } }
            }
            if !recommended.isEmpty {
                Section("Recommended for this \(device)") {
                    ForEach(recommended) { entry in row(entry) }
                }
                .accessibilityIdentifier("hub.recommended")
            }
            if !families.isEmpty || !ungrouped.isEmpty {
                Section("Available") {
                    ForEach(families) { family in
                        NavigationLink {
                            FamilyDetailView(family: family, filter: filter)
                        } label: {
                            FamilyRow(family: family)
                        }
                    }
                    ForEach(ungrouped) { entry in row(entry) }
                }
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    Button("Search Hugging Face for “\(query)”", systemImage: "magnifyingglass") { showsRepoSearch = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("hub.list")
        .navigationTitle("Manage models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search models")
        .overlay {
            if isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No models", systemImage: "cube",
                                           description: Text("Pull down to refresh the catalog, or add a model by link."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .toolbar { toolbarContent }
        .refreshable { await hub.refreshCatalog() }
        .sheet(isPresented: $showsRepoSearch) { RepoSearchSheet(query: query).presentationSizing(.page) }
        .sheet(isPresented: $showsAddByLink) { AddByLinkSheet() }
        .confirmationDialog("Delete model?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { entry in
            Button("Delete \(entry.descriptor.displayName)", role: .destructive) {
                Task { await hub.delete(modelID: entry.id) }
            }
        } message: { _ in
            Text("The files are removed from this \(device). You can download it again later.")
        }
        .confirmationDialog("Download anyway?", isPresented: Binding(get: { pendingDownload != nil }, set: { if !$0 { pendingDownload = nil } }),
                            titleVisibility: .visible, presenting: pendingDownload) { entry in
            Button("Download anyway", role: .destructive) { hub.download(entry) }
        } message: { entry in
            Text(FitText.downloadWarning(entry.fitDetail, sizeText: HubLogic.sizeText(entry.descriptor.sizeBytes), device: device) ?? "")
        }
        .onChange(of: installedIDs) { Task { await models.refresh() } }
        .task {
            await app.memory.refresh()
            freeBytes = Self.freeDiskBytes()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(FamilySort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("hub.sort")
            Menu {
                Toggle("Fits this \(device)", isOn: $filter.fitsOnly)
                Section("Engine") {
                    ForEach([ModelSource.gguf, .mlx], id: \.self) { source in
                        Toggle(HubListOptions.engineName(source), isOn: engineBinding(source))
                    }
                }
                let tags = FamilyLogic.tags(in: hub.families)
                if !tags.isEmpty {
                    Section("Capabilities") {
                        ForEach(tags, id: \.self) { name in
                            Toggle(name.capitalized, isOn: tagBinding(name))
                        }
                    }
                }
                Section("Size") {
                    ForEach(SizeBucket.allCases) { bucket in
                        Toggle(bucket.title, isOn: sizeBinding(bucket))
                    }
                }
                if filter.isChanged { Button("Reset filters", role: .destructive) { filter = FamilyFilter() } }
            } label: {
                Label("Filter", systemImage: filter.isChanged
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier("hub.filter")
            Button("Add by link", systemImage: "plus") { showsAddByLink = true }
                .accessibilityIdentifier("hub.add")
        }
    }

    private func engineBinding(_ source: ModelSource) -> Binding<Bool> {
        Binding(
            get: { filter.engines.contains(source) },
            set: { on in if on { filter.engines.insert(source) } else { filter.engines.remove(source) } }
        )
    }

    private func tagBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { filter.tags.contains(name) },
            set: { on in if on { filter.tags.insert(name) } else { filter.tags.remove(name) } }
        )
    }

    private func sizeBinding(_ bucket: SizeBucket) -> Binding<Bool> {
        Binding(
            get: { filter.sizes.contains(bucket) },
            set: { on in if on { filter.sizes.insert(bucket) } else { filter.sizes.remove(bucket) } }
        )
    }

    // MARK: Rows

    private func appleRow(_ model: ModelDescriptor) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ModelLabel(model: model)
                Text("Built in · On device").font(.subheadline).foregroundStyle(.secondary)
            }
            if models.selected?.id == model.id {
                Spacer()
                Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Default model")
            }
        }
        .contextMenu { Button("Set as default", systemImage: "star") { models.select(model) } }
    }

    private func row(_ entry: LocalModelEntry) -> some View {
        let id = entry.id
        let state = hub.downloadState(for: id)
        return NavigationLink {
            ModelDetailView(entry: entry)
        } label: {
            ModelRow(entry: entry, state: state, isDefault: models.selected?.id == id && state == .installed)
        }
        .swipeActions(edge: .trailing) { swipeActions(entry, state: state) }
        .contextMenu { menu(entry, state: state) }
    }

    @ViewBuilder
    private func swipeActions(_ entry: LocalModelEntry, state: DownloadState) -> some View {
        switch state {
        case .installed:
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
        case .downloading:
            Button("Cancel", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
            Button("Pause", systemImage: "pause") { hub.pause(modelID: entry.id) }.tint(.orange)
        case .paused:
            Button("Cancel", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
            Button("Resume", systemImage: "play") { hub.resume(modelID: entry.id) }.tint(.green)
        case .notInstalled, .failed:
            if entry.unavailableReason == nil {
                Button("Download", systemImage: "arrow.down") { requestDownload(entry) }.tint(.blue)
            }
        case .verifying:
            EmptyView()
        }
    }

    @ViewBuilder
    private func menu(_ entry: LocalModelEntry, state: DownloadState) -> some View {
        switch state {
        case .installed:
            if let descriptor = models.models.first(where: { $0.id == entry.id && $0.isInstalled }) {
                Button("Set as default", systemImage: "star") { models.select(descriptor) }
            }
            if app.memory.loadedModelID == entry.id {
                Button("Unload", systemImage: "memorychip") { Task { await app.memory.unload() } }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
        case .downloading:
            Button("Pause", systemImage: "pause") { hub.pause(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .paused:
            Button("Resume", systemImage: "play") { hub.resume(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .notInstalled, .failed:
            if entry.unavailableReason == nil {
                Button("Download", systemImage: "arrow.down.circle") { requestDownload(entry) }
            }
        case .verifying:
            EmptyView()
        }
    }

    /// A model that will not fit asks first. Everything else downloads at once.
    private func requestDownload(_ entry: LocalModelEntry) {
        let warning = FitText.downloadWarning(entry.fitDetail, sizeText: HubLogic.sizeText(entry.descriptor.sizeBytes), device: device)
        if warning != nil { pendingDownload = entry } else { hub.download(entry) }
    }

    private static func freeDiskBytes() -> Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Hugging Face repo search: pick a repo, then open one of its files or its snapshot.
struct RepoSearchSheet: View {
    let query: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var hits: [RepoHit] = []
    @State private var isLoading = true
    @State private var errorText: String?

    private var hub: any ModelHubService { app.hub }

    var body: some View {
        NavigationStack {
            List {
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                ForEach(hits) { hit in
                    NavigationLink {
                        RepoFilesView(hit: hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.repo)
                            Text(subtitle(hit)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Hugging Face")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoading { ProgressView() }
                else if hits.isEmpty && errorText == nil { ContentUnavailableView.search(text: query) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
        }
        .task { await search() }
    }

    private func subtitle(_ hit: RepoHit) -> String {
        var parts = [HubListOptions.engineName(hit.source)]
        if let d = hit.downloads { parts.append("\(d.formatted(.number.notation(.compactName))) downloads") }
        return parts.joined(separator: " · ")
    }

    private func search() async {
        isLoading = true
        do { hits = try await hub.searchRepos(query) } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}

/// The files (or snapshot) of one repo as model rows.
private struct RepoFilesView: View {
    let hit: RepoHit

    @Environment(AppState.self) private var app

    @State private var files: [LocalModelEntry] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            ForEach(files) { entry in
                NavigationLink {
                    ModelDetailView(entry: entry)
                } label: {
                    ModelRow(entry: entry, state: app.hub.downloadState(for: entry.id))
                }
            }
        }
        .navigationTitle(hit.repo)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
            else if files.isEmpty && errorText == nil {
                ContentUnavailableView("No usable files", systemImage: "doc", description: Text("This repo has no model files the app can run."))
            }
        }
        .task {
            do { files = try await app.hub.entries(for: hit) } catch { errorText = error.localizedDescription }
            isLoading = false
        }
    }
}

/// Add a model by Hugging Face link or repo id.
struct AddByLinkSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var format = ModelSource.gguf
    @State private var errorText: String?
    @State private var isBusy = false

    private var repo: String? { SettingsLogic.parseRepo(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("huggingface.co/org/model", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("hub.add.field")
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                } footer: {
                    Text("Paste a Hugging Face link or write org/model.")
                }
                Section {
                    Picker("Format", selection: $format) {
                        Text("GGUF").tag(ModelSource.gguf)
                        Text("MLX").tag(ModelSource.mlx)
                    }
                    .pickerStyle(.segmented)
                }
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add by link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) { add() }.disabled(repo == nil || isBusy)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationSizing(.form)
    }

    private func add() {
        guard let repo else { return }
        isBusy = true
        Task {
            do {
                try await app.hub.addRepo(RepoHit(repo: repo, source: format, downloads: nil, likes: nil))
                await app.hub.reload()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isBusy = false
        }
    }
}
