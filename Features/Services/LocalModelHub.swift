import Foundation
import Observation

/// Bridges the local model catalog and download manager (lane C) to the UI's `ModelHubService`.
@MainActor @Observable
final class LocalModelHub: ModelHubService {
    struct HubError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var catalog: [LocalModelEntry] = []
    private(set) var lastError: String?
    private(set) var remoteCatalogURL: String = ""
    private(set) var usesDevelopmentCatalog = false
    private(set) var memoryLimitNote: String?

    let downloads: ModelDownloadManager
    @ObservationIgnored private let service: CatalogService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let memory: @Sendable () -> DeviceMemory
    /// Whether the increased memory limit is signed into this install. Reads the executable: runs off the main actor.
    @ObservationIgnored private let entitlementSigned: @Sendable () -> Bool?
    /// Frees a model's weights after its files are deleted.
    @ObservationIgnored private let unloadModel: @Sendable (String) async -> Void
    /// Read at each reload, so every card of one list is judged against the same numbers.
    @ObservationIgnored private var deviceMemory: DeviceMemory
    @ObservationIgnored private var raw: [String: CatalogEntry] = [:]
    @ObservationIgnored private var browsed: [String: CatalogEntry] = [:]
    @ObservationIgnored private var restored = false

    init(downloads: ModelDownloadManager = ModelDownloadManager(),
         service: CatalogService = CatalogService(),
         defaults: UserDefaults = .standard,
         memory: @escaping @Sendable () -> DeviceMemory = { DeviceMemory.current() },
         entitlementSigned: @escaping @Sendable () -> Bool? = { MemoryEntitlement.isSignedForThisApp() },
         unloadModel: @escaping @Sendable (String) async -> Void = { _ in }) {
        self.downloads = downloads
        self.service = service
        self.defaults = defaults
        self.memory = memory
        self.entitlementSigned = entitlementSigned
        self.unloadModel = unloadModel
        self.deviceMemory = memory()
        downloads.backgroundCompletionHandler = {
            Task { @MainActor in AppDelegate.finishBackgroundEvents() }
        }
    }

    func reload() async {
        deviceMemory = memory()
        let signed = entitlementSigned
        memoryLimitNote = FitText.memoryLimitNote(entitlementSigned: await Task.detached(priority: .utility) { signed() }.value)
        if !restored {
            restored = true
            await downloads.restore()
        }
        let settings = CatalogSettings.load(from: defaults)
        remoteCatalogURL = settings.remoteCatalogURL?.absoluteString ?? ""
        usesDevelopmentCatalog = settings.useDevelopmentCatalog
        do {
            let entries = try await service.entries()
            let userIDs = Set(settings.userModels.map(\.id))
            raw = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            downloads.refresh(entries: entries)
            // A deprecated model is hidden unless it is installed: it keeps working, with a note about its replacement.
            let familyNames = Dictionary(
                entries.compactMap { entry in entry.familyID.flatMap { id in entry.familyName.map { (id, $0) } } },
                uniquingKeysWith: { first, _ in first })
            catalog = entries
                .filter { $0.status == .current || downloads.state(for: $0) == .installed }
                .map { map($0, isUser: userIDs.contains($0.id), replacementName: $0.replacedBy.flatMap { familyNames[$0] }) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCatalog() async {
        // A failed or bad remote file must not break the hub: keep what is cached and bundled.
        _ = try? await service.refreshRemote()
        await reload()
    }

    func downloadState(for modelID: String) -> DownloadState {
        guard let entry = raw[modelID] ?? browsed[modelID] else { return .notInstalled }
        let state = downloads.state(for: entry)
        switch state {
        case .notInstalled: return .notInstalled
        case .downloading: return .downloading(progress: state.fraction)
        case .paused: return .paused(progress: state.fraction)
        case .verifying: return .verifying
        case .installed: return .installed
        case .failed(let message): return .failed(message)
        }
    }

    func download(_ entry: LocalModelEntry) {
        guard let item = raw[entry.id] ?? browsed[entry.id] else { return }
        let known = raw[entry.id] != nil
        Task {
            if !known { await persist(adding: [item]) }
            await downloads.start(item)
        }
    }

    func pause(modelID: String) { if let e = raw[modelID] { downloads.pause(e) } }
    func resume(modelID: String) { if let e = raw[modelID] { downloads.resume(e) } }
    func cancel(modelID: String) { if let e = raw[modelID] { downloads.cancel(e) } }

    func delete(modelID: String) async {
        guard let entry = raw[modelID] else { return }
        // Files first: a chat that starts after this finds no model to load, and the unload below drops a load that
        // began before. Unloading first would let a chat load the model again before its files go.
        do {
            try downloads.delete(entry)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await unloadModel(modelID)
    }

    func searchRepos(_ query: String) async throws -> [RepoHit] {
        async let gguf = service.search(query: query, format: .gguf)
        async let mlx = service.search(query: query, format: .mlx)
        let (g, m) = try await (gguf, mlx)
        let hits = g.map { RepoHit(repo: $0.id, source: .gguf, downloads: $0.downloads, likes: $0.likes) }
            + m.map { RepoHit(repo: $0.id, source: .mlx, downloads: $0.downloads, likes: $0.likes) }
        return hits.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
    }

    func entries(for hit: RepoHit) async throws -> [LocalModelEntry] {
        deviceMemory = memory()
        let items = try await service.entries(forRepo: hit.repo, format: format(hit.source))
        for item in items where raw[item.id] == nil { browsed[item.id] = item }
        return items.map { map($0, isUser: false) }
    }

    func addRepo(_ hit: RepoHit) async throws {
        let items = try await service.entries(forRepo: hit.repo, format: format(hit.source))
        await persist(adding: items)
    }

    func removeUserModel(modelID: String) async {
        var settings = CatalogSettings.load(from: defaults)
        settings.remove(id: modelID)
        save(settings)
        await reload()
    }

    func setRemoteCatalogURL(_ text: String) async throws {
        var settings = CatalogSettings.load(from: defaults)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.remoteCatalogURL = nil
        } else {
            guard let url = URL(string: trimmed), CatalogSettings.isAcceptableRemoteCatalogURL(url) else {
                throw HubError(message: "Enter an https URL.")
            }
            settings.remoteCatalogURL = url
        }
        try settings.save(to: defaults)
        _ = try await service.refreshRemote()
        await reload()
    }

    func setUsesDevelopmentCatalog(_ on: Bool) async {
        var settings = CatalogSettings.load(from: defaults)
        settings.useDevelopmentCatalog = on
        save(settings)
        await refreshCatalog()
    }

    // MARK: - Private

    private func persist(adding items: [CatalogEntry]) async {
        var settings = CatalogSettings.load(from: defaults)
        settings.add(items.map { var e = $0; e.origin = .user; return e })
        save(settings)
        await reload()
    }

    private func save(_ settings: CatalogSettings) {
        do {
            try settings.save(to: defaults)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func format(_ source: ModelSource) -> LocalModelFormat {
        source == .mlx ? .mlx : .gguf
    }

    private func map(_ entry: CatalogEntry, isUser: Bool, replacementName: String? = nil) -> LocalModelEntry {
        var tags = [entry.format == .mlx ? "mlx" : "gguf"]
        if let parameters = entry.parameters { tags.append(parameters) }
        if let quantization = entry.quantization { tags.append(quantization) }
        tags += entry.capabilities.subtracting(["chat"]).sorted()
        var verdict = ModelFit.unknown
        var detail: FitDetail?
        if let profile = entry.memoryProfile {
            let estimate = FitPlanner.estimate(profile, memory: deviceMemory)
            switch estimate.verdict {
            case .runsWell: verdict = .fits
            case .tight: verdict = .tight
            case .wontFit: verdict = .wontFit
            }
            var maxReply = FitPlanner.maxReply(forContext: estimate.context)
            if case .tight(_, let reply) = estimate.verdict { maxReply = reply }
            detail = FitDetail(
                verdict: verdict, neededBytes: estimate.totalBytes, budgetBytes: estimate.deviceBudgetBytes,
                context: estimate.context, maxReply: maxReply, streamsFromStorage: estimate.streamsFromStorage,
                isEstimate: estimate.isEstimated)
        }
        let installed = downloads.state(for: entry) == .installed
        var unavailable: String?
        if entry.format == .mlx, case .unavailable(let reason) = MLXEngine.availability { unavailable = reason }
        return LocalModelEntry(
            descriptor: ModelDescriptor(
                id: entry.id,
                source: entry.format == .mlx ? .mlx : .gguf,
                displayName: entry.title,
                contextLength: entry.contextLength,
                capabilities: entry.capabilities,
                sizeBytes: entry.sizeBytes,
                isInstalled: installed
            ),
            summary: entry.summary ?? entry.repo,
            tags: tags,
            fit: verdict,
            isUserAdded: isUser,
            unavailableReason: unavailable,
            badges: entry.badges.map { ModelBadge(label: $0.label, tone: ModelBadge.Tone(rawValue: $0.tone ?? "") ?? .neutral) },
            fitDetail: detail,
            isOnboarding: entry.isOnboarding,
            isRecommended: entry.recommended,
            familyID: entry.familyID,
            familyName: entry.familyName,
            publisher: entry.publisher,
            logo: entry.iconKey,
            website: entry.website,
            parameters: entry.parameters,
            parameterBillions: FamilyLogic.billions(of: entry.parameters),
            quantization: entry.quantization,
            releasedAt: entry.updatedAt ?? entry.createdAt,
            isDeprecated: entry.status == .deprecated,
            replacementName: replacementName
        )
    }
}
