import SwiftUI

/// Sheet wrapper: the hub in its own navigation stack with a Done button.
struct HubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HubScreen()
                .navigationTitle("Browse Models")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .tint(ARColor.accent)
    }
}

/// Browse Models content: installed and available local models, Hugging Face search, downloads.
struct HubScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var query = ""
    @State private var showsRepoSearch = false

    private var hub: any ModelHubService { app.hub }

    private var sections: HubLogic.Sections {
        HubLogic.sections(catalog: hub.catalog, state: { hub.downloadState(for: $0) }, query: query)
    }

    private var installedIDs: [String] {
        hub.catalog.filter { hub.downloadState(for: $0.id) == .installed }.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = hub.lastError { ErrorBanner(text: error) {} }
                    installedSection
                    availableSection
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty { searchRow }
                }
                .frame(maxWidth: ARTheme.contentMaxWidth)
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .searchable(text: $query, prompt: "Search models")
        .refreshable { await hub.reload() }
        .sheet(isPresented: $showsRepoSearch) {
            RepoSearchSheet(query: query)
        }
        .onChange(of: installedIDs) {
            Task { await models.refresh() }
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        let apple = models.models.filter { $0.source == .apple && $0.isInstalled }
        if !sections.installed.isEmpty || !apple.isEmpty {
            ARSectionTitle("Installed Models")
            ForEach(apple) { _ in
                ModelCard(title: "Apple Intelligence", sizeText: nil,
                          summary: "Apple Intelligence is a model for local use.",
                          tags: ["local", "apple"], leadingIcon: "apple.logo")
            }
            ForEach(sections.installed) { entry in card(entry) }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        if !sections.available.isEmpty {
            ARSectionTitle("Browse Models").padding(.top, 8)
            ForEach(sections.available) { entry in card(entry) }
        } else if sections.isEmpty && !query.isEmpty {
            Text("No matching models").font(.arSM).foregroundStyle(ARColor.mutedForeground).padding(.top, 24)
        }
    }

    private func card(_ entry: LocalModelEntry) -> some View {
        let id = entry.id
        return ModelCard(
            title: entry.descriptor.displayName,
            sizeText: HubLogic.sizeText(entry.descriptor.sizeBytes),
            summary: entry.summary,
            tags: entry.tags,
            fit: entry.fit,
            state: hub.downloadState(for: id),
            unavailableReason: entry.unavailableReason,
            onDownload: { hub.download(entry) },
            onPause: { hub.pause(modelID: id) },
            onResume: { hub.resume(modelID: id) },
            onCancel: { hub.cancel(modelID: id) },
            onDelete: { Task { await hub.delete(modelID: id) } }
        )
    }

    private var searchRow: some View {
        Button { showsRepoSearch = true } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search Hugging Face for “\(query)”").font(.arBase)
                Spacer()
                Image(systemName: "chevron.right").font(.arXS)
            }
            .foregroundStyle(ARColor.foreground)
            .padding(14)
            .arCard(radius: ARTheme.radiusLarge)
        }
        .buttonStyle(.plain)
    }
}

/// Hugging Face repo search: pick a repo, then download one of its files or snapshot.
struct RepoSearchSheet: View {
    let query: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var hits: [RepoHit] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selected: RepoHit?
    @State private var files: [LocalModelEntry] = []
    @State private var isLoadingFiles = false

    private var hub: any ModelHubService { app.hub }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if selected != nil {
                    ARIconButton(systemName: "arrow.left", label: "Back") { selected = nil; files = [] }
                }
                Text(selected?.repo ?? "Hugging Face").font(.arXL).foregroundStyle(ARColor.foreground).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(ARTheme.pagePadding)
            ScrollView {
                VStack(spacing: 10) {
                    if let errorText { ErrorBanner(text: errorText) { self.errorText = nil } }
                    if selected == nil { repoList } else { fileList }
                }
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
            }
        }
        .background(ARColor.background.ignoresSafeArea())
        .presentationDetents([.large])
        .task { await search() }
    }

    @ViewBuilder
    private var repoList: some View {
        if isLoading {
            ProgressView().padding(.top, 32)
        } else if hits.isEmpty {
            Text("No models found").font(.arSM).foregroundStyle(ARColor.mutedForeground).padding(.top, 32)
        }
        ForEach(hits) { hit in
            Button { open(hit) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.repo).font(.arBase).foregroundStyle(ARColor.foreground).lineLimit(1)
                        HStack(spacing: 6) {
                            ARChip(text: hit.source == .mlx ? "mlx" : "gguf")
                            if let d = hit.downloads { Text("\(d.formatted(.number.notation(.compactName))) downloads").font(.arXS).foregroundStyle(ARColor.mutedForeground) }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.arXS).foregroundStyle(ARColor.mutedForeground)
                }
                .padding(12)
                .arCard(radius: ARTheme.radius)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if isLoadingFiles {
            ProgressView().padding(.top, 32)
        } else if files.isEmpty {
            Text("No usable files in this repo").font(.arSM).foregroundStyle(ARColor.mutedForeground).padding(.top, 32)
        }
        ForEach(files) { entry in
            let id = entry.id
            ModelCard(
                title: entry.descriptor.displayName,
                sizeText: HubLogic.sizeText(entry.descriptor.sizeBytes),
                summary: entry.summary, tags: entry.tags, fit: entry.fit,
                state: hub.downloadState(for: id),
            unavailableReason: entry.unavailableReason,
                onDownload: { hub.download(entry) },
                onPause: { hub.pause(modelID: id) },
                onResume: { hub.resume(modelID: id) },
                onCancel: { hub.cancel(modelID: id) },
                onDelete: { Task { await hub.delete(modelID: id) } }
            )
        }
    }

    private func search() async {
        isLoading = true
        do { hits = try await hub.searchRepos(query) } catch { errorText = error.localizedDescription }
        isLoading = false
    }

    private func open(_ hit: RepoHit) {
        selected = hit
        isLoadingFiles = true
        Task {
            do { files = try await hub.entries(for: hit) } catch { errorText = error.localizedDescription }
            isLoadingFiles = false
        }
    }
}
