import SwiftUI

/// One picker row. Line 1: logo, name and rank. Line 2: price, context, capability symbols and weekly use.
/// Two lines of fixed size, so the list keeps one row height. At accessibility text sizes the row stacks
/// and wraps instead (see `RowLayout`).
struct ModelRowView: View {
    let row: ModelRowModel
    let isCurrent: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 26

    var body: some View {
        let layout = RowLayout.make(typeSize)
        return content(layout)
            .opacity(row.isDimmed ? 0.45 : 1)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("model-row.\(row.id)")
    }

    @ViewBuilder
    private func content(_ layout: RowLayout) -> some View {
        if layout.isStacked {
            stackedRow(layout)
        } else {
            compactRow(layout)
        }
    }

    private func compactRow(_ layout: RowLayout) -> some View {
        HStack(spacing: 12) {
            ModelLogo(brand: row.brand, size: logoSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title).font(.body).lineLimit(layout.titleLineLimit).layoutPriority(1)
                    Spacer(minLength: 0)
                    rankLabel
                }
                // The most informative line that fits, so a narrow row loses the usage first.
                ViewThatFits(in: .horizontal) {
                    detailLine(usage: row.usage?.weeklySummary)
                    detailLine(usage: row.usage?.summary)
                    detailLine(usage: nil)
                }
            }
            if isCurrent { currentMark }
        }
    }

    /// Accessibility sizes: the name may take as many lines as it needs, and each detail gets its own line.
    private func stackedRow(_ layout: RowLayout) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ModelLogo(brand: row.brand, size: logoSize)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title).font(.body).lineLimit(layout.titleLineLimit)
                    Spacer(minLength: 0)
                    rankLabel
                }
                VStack(alignment: .leading, spacing: 2) {
                    if row.isFree, let badge = row.details.first { freeBadge(badge) }
                    if !row.detailsAfterBadge.isEmpty { Text(row.detailsAfterBadge).lineLimit(layout.detailLineLimit) }
                    capabilityIcons
                    if let usage = row.usage?.weeklySummary { Text(usage).lineLimit(layout.detailLineLimit) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if isCurrent { currentMark }
        }
    }

    /// The standard list checkmark: body size, semibold, the app tint. Left to inherit, it drew about 44 pt and heavy
    /// on the operator's device.
    private var currentMark: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(.tint)
    }

    @ViewBuilder
    private var rankLabel: some View {
        if let usage = row.usage, let rank = row.rankText {
            Text(rank).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityLabel("Rank \(usage.rank) this week")
        }
    }

    /// The gift and "Free" sit as close as the other inline symbols; a `Label` would reserve its icon column.
    private func freeBadge(_ badge: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "gift").font(.caption2).imageScale(.small)
            Text(badge)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var capabilityIcons: some View {
        if !row.capabilities.isEmpty {
            // Small, tight symbols so they read as part of the line, not as buttons.
            HStack(spacing: 3) {
                ForEach(row.capabilities) { capability in
                    Image(systemName: capability.symbol).accessibilityLabel(capability.title)
                }
            }
            .font(.caption2)
            .imageScale(.small)
        }
    }

    private func detailLine(usage: String?) -> some View {
        HStack(spacing: 6) {
            if row.isFree, let badge = row.details.first { freeBadge(badge) }
            let rest = row.detailsAfterBadge
            if row.isFree && !rest.isEmpty { Text("·") }
            if !rest.isEmpty { Text(rest).lineLimit(1) }
            capabilityIcons
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
    /// A sheet closes with the × button; a popover (iPad) closes with a tap outside, so it has none.
    let showsClose: Bool

    @State private var tab: PickerTab
    @State private var query = ""
    /// `query` after a short pause, so a long list is not rebuilt on every keystroke.
    @State private var debouncedQuery = ""
    @State private var sort: PickerSort = .topUsage
    @State private var signInError: String?
    /// The cloud model a signed-out person tapped; the sign-in sheet is about it.
    @State private var signInModel: ModelDescriptor?
    @State private var keyExplainer: ModelDescriptor?
    @State private var routerDetail: ModelDescriptor?
    @State private var detailModel: ModelDescriptor?
    @State private var detent = PresentationDetent.large
    @State private var cloudFilter: ModelFilter
    @State private var localFilter: LocalFilter
    @State private var showsFilters = false
    /// "Show all models" was tapped. Searching, sorting and filtering also leave the short view.
    @State private var showsAll = false

    private let filterStore: PickerFilterStore

    private let picksConfig = TopPicksConfig.bundled()
    private static let providerKeysURL = URL(string: "https://anyrouter.dev/dashboard/byok")!

    init(currentID: String?, showsClose: Bool = true, defaults: UserDefaults = PickerFilterStore.standardDefaults,
         onSelect: @escaping (ModelDescriptor) -> Void) {
        self.currentID = currentID
        self.showsClose = showsClose
        self.onSelect = onSelect
        let store = PickerFilterStore(defaults: defaults)
        filterStore = store
        _cloudFilter = State(initialValue: store.cloud())
        _localFilter = State(initialValue: store.local())
        _tab = State(initialValue: currentID?.hasPrefix("anyrouter/") == true ? .anyrouter : .local)
        _detent = State(initialValue: DemoData.opensPickerAtMedium ? .medium : .large)
    }

    /// What the current tab shows. Built once per body, not once per subview that needs it.
    private struct Shown {
        var local: [ModelDescriptor] = []
        var cloud = CloudList(topPicks: [], rest: [])
    }

    private var shown: Shown {
        switch tab {
        case .local: Shown(local: localModels)
        case .anyrouter: Shown(cloud: cloudList)
        }
    }

    var body: some View {
        let shown = shown
        return NavigationStack {
            List {
                if app.network.isOffline { offlineSection }
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
            .navigationDestination(isPresented: $showsFilters) {
                ModelFilterForm(
                    tab: tab, cloud: $cloudFilter, local: $localFilter,
                    providers: ModelFilter.providers(in: models.models))
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
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showsFilters = true } label: {
                        Label("Filter", systemImage: filterActive
                            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityValue(filterActive ? "\(activeFilterCount) active" : "none")
                    .accessibilityIdentifier("model-filter")
                }
                if tab == .anyrouter {
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
        .sheet(item: $signInModel) { model in
            CloudSignInSheet(
                model: model, error: signInError, isWorking: isSigningIn,
                signIn: { signIn($0, for: model) }, notNow: { signInModel = nil })
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

    // MARK: - Offline

    /// Without a connection the cloud models cannot answer. The picker says so and offers the model on this device.
    private var offlineSection: some View {
        Section {
            Label(OfflineLogic.pickerNote, systemImage: "wifi.slash")
            if let suggestion = OfflineLogic.suggestedModel(in: models.models) {
                Button { choose(suggestion) } label: { Label("Use \(suggestion.shortName)", systemImage: "iphone") }
                    .accessibilityIdentifier("model-picker.offline-suggestion")
            }
        } header: {
            Text(OfflineLogic.label)
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
            // A row at the end of the list, not a button floating over it: at the medium height the floating one
            // covered the last model (operator's device).
            Button {
                dismiss()
                shell.open(.hub, closeSidebar: true)
            } label: {
                Label("Browse models", systemImage: "square.stack.3d.up")
            }
            .accessibilityIdentifier("model-picker.browse")
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
            filter: cloudFilter, prefs: models.cloudPrefs, currentID: currentID,
            short: !showsAll && sort == .topUsage && !cloudFilter.isActive, signedIn: app.account.state.isSignedIn)
    }

    @ViewBuilder
    private func cloudRows(_ list: CloudList) -> some View {
        if let failure = models.loadFailures[.anyrouter], !models.isLoading, !list.isEmpty {
            CloudListStaleNotice(message: failure) { Task { await models.refresh() } }
        }
        if let current = list.current {
            Section("Current") { modelButton(current) }
        }
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
                if list.isShort {
                    Text("Top this week")
                } else if !list.topPicks.isEmpty || !list.starred.isEmpty {
                    Text("All models")
                }
            }
        }
        if list.moreCount > 0 {
            Section {
                Button("Show all models") { showsAll = true }
                    .accessibilityIdentifier("show-all-models")
            } footer: {
                Text("\(list.moreCount) more. Search to find any model.")
            }
        }
    }

    @ViewBuilder
    private func stateOverlay(_ shown: Shown) -> some View {
        if tab == .anyrouter {
            // The list is public, so it shows signed out too. Only an empty list needs saying why.
            if shown.cloud.isEmpty {
                if debouncedQuery.isEmpty && !cloudFilter.isActive {
                    CloudListEmptyState(
                        reason: CloudEmptyReason.reason(
                            models: models.models, failure: models.loadFailures[.anyrouter], isLoading: models.isLoading),
                        retry: { Task { await models.refresh() } })
                } else {
                    noMatches(clear: { cloudFilter = ModelFilter() }, isFiltered: cloudFilter.isActive)
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
        let skipped = app.network.isOffline && OfflineLogic.needsNetwork(model)
        return HStack(spacing: 8) {
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
            .disabled(skipped)
            if skipped { Text(OfflineLogic.label).font(.footnote).foregroundStyle(.secondary) }
        }
        // One trailing accessory, the checkmark: details open with a swipe or a long press, not a second ⓘ that cut
        // the row's details short (HIG audit 2026-11-28 #15).
        .swipeActions(edge: .trailing) {
            if model.source == .anyrouter {
                Button("Details", systemImage: "info.circle") { detailModel = model }
                    .tint(.gray)
                    .accessibilityIdentifier("model-info.\(model.id)")
            }
        }
        .contextMenu {
            if model.source == .anyrouter {
                Button("Details", systemImage: "info.circle") { detailModel = model }
            }
        }
        .accessibilityActions {
            if model.source == .anyrouter {
                Button("Details") { detailModel = model }
            }
        }
    }

    /// A router's detail screen can open the list of models it picks from.
    private func showRouting(for model: ModelDescriptor) -> (() -> Void)? {
        guard model.isRouter, (model.cloud?.memberCount ?? 0) > 0 else { return nil }
        return { routerDetail = model }
    }

    private func choose(_ model: ModelDescriptor) {
        switch CloudSignInLogic.tap(model, signedIn: app.account.state.isSignedIn) {
        case .select:
            onSelect(model)
            dismiss()
        case .signIn:
            signInError = nil
            signInModel = model
        case .explainKey:
            keyExplainer = model
        case .ignore:
            break
        }
    }

    private var isSigningIn: Bool {
        if case .signingIn = app.account.state { return true }
        return false
    }

    /// Signs in or up from the sheet. After a good sign-in the tapped model becomes the pick.
    private func signIn(_ mode: AuthMode, for model: ModelDescriptor) {
        signInError = nil
        Task {
            do {
                let outcome = try await CloudSignInLogic.signIn(mode: mode, then: model, account: app.account, models: models)
                switch outcome {
                case .selected(let picked):
                    signInModel = nil
                    choose(picked)
                case .signedInOnly: signInModel = nil
                case .stillSignedOut: break
                }
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
