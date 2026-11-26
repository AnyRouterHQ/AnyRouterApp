import SwiftUI

/// One picker row. Line 1: logo, name and rank. Line 2: price, context, capability symbols and weekly use.
/// Two lines of fixed size, so the list keeps one row height.
struct ModelRowView: View {
    let row: ModelRowModel
    let isCurrent: Bool

    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 12) {
            ModelLogo(brand: row.brand, size: logoSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title).font(.body).lineLimit(1).layoutPriority(1)
                    if !row.idLabel.isEmpty {
                        Text(row.idLabel).font(.footnote).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if let usage = row.usage, let rank = row.rankText {
                        Text(rank).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityLabel("Rank \(usage.rank) this week")
                    }
                }
                // The most informative line that fits, so a narrow row or a large text size loses the usage first.
                ViewThatFits(in: .horizontal) {
                    detailLine(usage: row.usage?.weeklySummary)
                    detailLine(usage: row.usage?.summary)
                    detailLine(usage: nil)
                }
            }
            if isCurrent { Image(systemName: "checkmark").fontWeight(.semibold) }
        }
        .opacity(row.isDimmed ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("model-row.\(row.id)")
    }

    private func detailLine(usage: String?) -> some View {
        HStack(spacing: 6) {
            if row.isFree, let badge = row.details.first {
                Label(badge, systemImage: "gift").labelStyle(.titleAndIcon)
            }
            let rest = row.detailsAfterBadge
            if row.isFree && !rest.isEmpty { Text("·") }
            if !rest.isEmpty { Text(rest).lineLimit(1) }
            ForEach(row.capabilities) { capability in
                Image(systemName: capability.symbol).accessibilityLabel(capability.title)
            }
            Spacer(minLength: 0)
            if let usage { Text(usage).lineLimit(1) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// Model picker: a Local tab and an AnyRouter tab, searchable, with a sort menu for cloud models.
struct ModelPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The model the chat uses now.
    let currentID: String?
    /// Called with the pick; the chat applies it to the next message.
    let onSelect: (ModelDescriptor) -> Void

    @State private var tab: PickerTab
    @State private var query = ""
    /// `query` after a short pause, so a long list is not rebuilt on every keystroke.
    @State private var debouncedQuery = ""
    @State private var sort: PickerSort = .topUsage
    @State private var signInError: String?
    @State private var keyExplainer: ModelDescriptor?
    @State private var routerDetail: ModelDescriptor?
    @State private var detailModel: ModelDescriptor?
    @State private var detent = PresentationDetent.large
    @State private var cloudFilter: ModelFilter
    @State private var localFilter: LocalFilter
    @State private var showsFilters = false

    private let filterStore: PickerFilterStore

    private let picksConfig = TopPicksConfig.bundled()
    private static let providerKeysURL = URL(string: "https://anyrouter.dev/dashboard/byok")!

    init(currentID: String?, defaults: UserDefaults = PickerFilterStore.standardDefaults, onSelect: @escaping (ModelDescriptor) -> Void) {
        self.currentID = currentID
        self.onSelect = onSelect
        let store = PickerFilterStore(defaults: defaults)
        filterStore = store
        _cloudFilter = State(initialValue: store.cloud())
        _localFilter = State(initialValue: store.local())
        _tab = State(initialValue: currentID?.hasPrefix("anyrouter/") == true ? .anyrouter : .local)
    }

    /// What the current tab shows. Built once per body, not once per subview that needs it.
    private struct Shown {
        var local: [ModelDescriptor] = []
        var cloud = CloudList(topPicks: [], rest: [])
    }

    private var shown: Shown {
        switch tab {
        case .local: Shown(local: localModels)
        case .anyrouter: app.account.state.isSignedIn ? Shown(cloud: cloudList) : Shown()
        }
    }

    var body: some View {
        let shown = shown
        return NavigationStack {
            List {
                switch tab {
                case .local: localRows(shown.local)
                case .anyrouter: cloudRows(shown.cloud)
                }
            }
            .navigationDestination(item: $detailModel) { model in
                CloudModelDetailView(
                    model: model, usage: models.weeklyUsage[model.wireID],
                    onShowRouting: showRouting(for: model))
            }
            .overlay { stateOverlay(shown) }
            .task(id: query) {
                if query.isEmpty { debouncedQuery = ""; return }
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { debouncedQuery = query }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search models")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Source", selection: $tab) {
                    ForEach(PickerTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if tab == .local {
                    Button {
                        dismiss()
                        shell.open(.hub, closeSidebar: true)
                    } label: {
                        Label("Browse models", systemImage: "square.stack.3d.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if tab == .local || app.account.state.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showsFilters = true } label: {
                            Label("Filter", systemImage: filterActive
                                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityValue(filterActive ? "\(activeFilterCount) active" : "none")
                        .accessibilityIdentifier("model-filter")
                    }
                }
                if tab == .anyrouter, app.account.state.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(PickerSort.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sheet(item: $routerDetail) { RouterDetailSheet(router: $0) }
        .sheet(isPresented: $showsFilters) {
            ModelFilterSheet(
                tab: tab, cloud: $cloudFilter, local: $localFilter,
                providers: ModelFilter.providers(in: models.models))
        }
        .onChange(of: cloudFilter) { filterStore.save(cloud: cloudFilter) }
        .onChange(of: localFilter) { filterStore.save(local: localFilter) }
        .alert("Needs your provider key", isPresented: Binding(
            get: { keyExplainer != nil }, set: { if !$0 { keyExplainer = nil } }
        )) {
            Button("Open provider keys") { openURL(Self.providerKeysURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(keyExplainer?.shortName ?? "This model") runs on your own provider account. Add the key in your AnyRouter dashboard, then pick it here.")
        }
    }

    // MARK: - Local tab

    private var localModels: [ModelDescriptor] {
        let needle = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = models.models.filter { model in
            switch model.source {
            case .apple: return true
            case .gguf, .mlx: return model.isInstalled
            case .anyrouter: return false
            }
        }
        let searched = needle.isEmpty ? local : local.filter { ModelPickerLogic.matches($0, needle) }
        let matched = searched.filter { localFilter.matches($0, fit: fitVerdict(for: $0)) }
        return matched.sorted { lhs, rhs in
            if (lhs.source == .apple) != (rhs.source == .apple) { return lhs.source == .apple }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    private func localRows(_ list: [ModelDescriptor]) -> some View {
        Section("Downloaded") {
            ForEach(list) { model in
                modelButton(model, fitBadge: fitBadge(for: model))
            }
        }
    }

    private func fitVerdict(for model: ModelDescriptor) -> ModelFit? {
        guard model.source == .gguf || model.source == .mlx else { return nil }
        return app.hub.catalog.first(where: { $0.id == model.id })?.fitDetail?.verdict
    }

    private var filterActive: Bool { tab == .local ? localFilter.isActive : cloudFilter.isActive }
    private var activeFilterCount: Int { tab == .local ? localFilter.activeCount : cloudFilter.activeCount }

    private func fitBadge(for model: ModelDescriptor) -> String? {
        guard model.source == .gguf || model.source == .mlx,
              let detail = app.hub.catalog.first(where: { $0.id == model.id })?.fitDetail else { return nil }
        return FitText.badge(detail, device: DeviceName.current)
    }

    // MARK: - AnyRouter tab

    private var cloudList: CloudList {
        CloudListLogic.arrange(
            models: models.models, query: debouncedQuery, sort: sort, usageRank: models.usageRank,
            showUnusable: app.account.state.isSignedIn,
            picks: TopPicks.compose(config: picksConfig, models: models.models, usageRank: models.usageRank),
            filter: cloudFilter, prefs: models.cloudPrefs)
    }

    @ViewBuilder
    private func cloudRows(_ list: CloudList) -> some View {
        if !list.starred.isEmpty {
            Section("Starred") { ForEach(list.starred) { modelButton($0) } }
        }
        if !list.topPicks.isEmpty {
            Section("Top picks") { ForEach(list.topPicks) { modelButton($0) } }
        }
        if !list.rest.isEmpty {
            Section {
                ForEach(list.rest) { modelButton($0) }
            } header: {
                if !list.topPicks.isEmpty || !list.starred.isEmpty { Text("All models") }
            }
        }
    }

    @ViewBuilder
    private func stateOverlay(_ shown: Shown) -> some View {
        if tab == .anyrouter {
            switch app.account.state {
            case .signedOut:
                ContentUnavailableView {
                    Label("Sign in to use cloud models", systemImage: "cloud")
                } description: {
                    Text("AnyRouter picks the best model for each message.")
                    if let signInError { Text(signInError).foregroundStyle(.red) }
                } actions: {
                    Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.borderedProminent)
                }
            case .signingIn:
                ProgressView("Signing in…")
            case .signedIn:
                if shown.cloud.isEmpty {
                    if debouncedQuery.isEmpty && !cloudFilter.isActive {
                        ContentUnavailableView("No cloud models", systemImage: "cloud")
                    } else {
                        noMatches(clear: { cloudFilter = ModelFilter() }, isFiltered: cloudFilter.isActive)
                    }
                }
            }
        } else if shown.local.isEmpty, !debouncedQuery.isEmpty || localFilter.isActive {
            noMatches(clear: { localFilter = LocalFilter() }, isFiltered: localFilter.isActive)
        }
    }

    /// Nothing matches the search or the filters. Filters can be cleared right here.
    private func noMatches(clear: @escaping () -> Void, isFiltered: Bool) -> some View {
        ContentUnavailableView {
            Label(debouncedQuery.isEmpty ? "No matching models" : "No results for “\(debouncedQuery)”", systemImage: "magnifyingglass")
        } description: {
            Text(isFiltered ? "Try a different search or clear the filters." : "Check the spelling or try a new search.")
        } actions: {
            if isFiltered { Button("Clear filters", action: clear).buttonStyle(.bordered) }
        }
    }

    // MARK: - Rows

    private func modelButton(_ model: ModelDescriptor, fitBadge: String? = nil) -> some View {
        HStack(spacing: 8) {
            Button {
                choose(model)
            } label: {
                ModelRowView(
                    row: PickerRow.make(
                        model, fitBadge: fitBadge,
                        usage: CloudListLogic.rowUsage(of: model, sort: sort, in: models.weeklyUsage)),
                    isCurrent: currentID == model.id)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            if model.source == .anyrouter {
                Button { detailModel = model } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Details for \(model.shortName)")
                    .accessibilityIdentifier("model-info.\(model.id)")
            }
        }
    }

    /// A router's detail screen can open the list of models it picks from.
    private func showRouting(for model: ModelDescriptor) -> (() -> Void)? {
        guard model.isRouter, (model.cloud?.memberCount ?? 0) > 0 else { return nil }
        return { routerDetail = model }
    }

    private func choose(_ model: ModelDescriptor) {
        guard model.isInstalled else {
            if model.cloud?.availability == .needsKey { keyExplainer = model }
            return
        }
        onSelect(model)
        dismiss()
    }

    private func signIn() {
        signInError = nil
        Task {
            do {
                try await app.account.signIn()
                await models.refresh()
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
