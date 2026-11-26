import Foundation
import Observation

/// Models from every engine plus the user's current choice (persisted).
@MainActor @Observable
final class ModelStore {
    private static let selectedKey = "models.selectedID"

    @ObservationIgnored private let registry: EngineRegistry
    @ObservationIgnored private let defaults: UserDefaults
    /// Shared with chats, which report through the same boundary.
    @ObservationIgnored let telemetry: any Telemetry

    private(set) var models: [ModelDescriptor] = []
    private(set) var isLoading = false
    /// True after the first refresh, so a missing model can be told apart from "not loaded yet".
    private(set) var hasLoaded = false
    /// Each model's last 7 days by wire id. From the cache until a fresh fetch lands; empty offline on first launch.
    private(set) var weeklyUsage: [String: ModelUsage] = [:]
    /// Wire id to place in the weekly usage order (0 is most used). Kept in step with `weeklyUsage`.
    private(set) var usageRank: [String: Int] = [:]
    private var selectedID: String?
    /// The person's stars and hidden cloud models. Saved at once, shared by the picker and Settings.
    private(set) var cloudPrefs = CloudModelPrefs()
    @ObservationIgnored private let usageSource: (any WeeklyUsageSource)?
    @ObservationIgnored private let usageCache: WeeklyUsageCache

    init(
        registry: EngineRegistry, defaults: UserDefaults = .standard, telemetry: any Telemetry = NoopTelemetry(),
        usage: (any WeeklyUsageSource)? = nil
    ) {
        self.registry = registry
        self.defaults = defaults
        self.telemetry = telemetry
        self.usageSource = usage
        self.usageCache = WeeklyUsageCache(defaults: defaults)
        self.selectedID = defaults.string(forKey: Self.selectedKey)
        self.cloudPrefs = CloudModelPrefs.load(from: defaults)
        apply(usageCache.load())
        Perf.beginModels()
    }

    /// The model for a chat that has no pick of its own. `preferredUnavailable` is set when a
    /// pick exists but cannot be used any more, so the chat shows a notice.
    struct Resolution: Equatable {
        var model: ModelDescriptor?
        var preferredUnavailable: Bool
    }

    /// The default for new chats: the last pick when still usable, else `DefaultModelPolicy`.
    var selected: ModelDescriptor? {
        DefaultModelPolicy.resolve(saved: selectedID, models: models)
    }

    /// Set once the models are loaded and the saved default can no longer be used: Settings says which model took over.
    var defaultNote: String? {
        hasLoaded ? DefaultModelPolicy.fallbackNote(saved: selectedID, models: models) : nil
    }

    /// The model a chat should use, given the model id saved on its thread (nil for a new chat).
    func resolve(preferred: String?) -> Resolution {
        guard let preferred else { return Resolution(model: selected, preferredUnavailable: false) }
        if let match = models.first(where: { $0.id == preferred && $0.isInstalled }) {
            return Resolution(model: match, preferredUnavailable: false)
        }
        return Resolution(model: selected, preferredUnavailable: hasLoaded)
    }

    func refresh() async {
        isLoading = true
        // Each engine's models appear as soon as it answers, so a slow cloud list never keeps Apple and local models waiting.
        for await listing in registry.modelListings() {
            models = listing
            if listing.contains(where: \.isInstalled) { Perf.endModels() }
        }
        isLoading = false
        hasLoaded = true
        await refreshWeeklyUsage()
    }

    /// A model listed twice keeps its best place.
    private func apply(_ usage: [ModelUsage]) {
        weeklyUsage = Dictionary(usage.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        usageRank = Dictionary(usage.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Fetches the weekly usage at most every 6 hours. A failure keeps the cached usage.
    func refreshWeeklyUsage(now: Date = Date()) async {
        guard let usageSource, !usageCache.isFresh(now: now) else { return }
        guard let usage = try? await usageSource.fetchWeeklyUsage(), !usage.isEmpty else { return }
        usageCache.save(usage, at: now)
        apply(usage)
    }

    /// Remembers the pick as the default for new chats.
    func select(_ model: ModelDescriptor) {
        selectedID = model.id
        defaults.set(model.id, forKey: Self.selectedKey)
        telemetry.track(.modelSelected(source: model.source))
    }

    func toggleStar(_ model: ModelDescriptor) { updatePrefs { $0.toggleStar(model.wireID) } }
    func hide(_ model: ModelDescriptor) { updatePrefs { $0.hide(model.wireID) } }
    func unhide(_ model: ModelDescriptor) { updatePrefs { $0.unhide(model.wireID) } }

    private func updatePrefs(_ change: (inout CloudModelPrefs) -> Void) {
        var prefs = cloudPrefs
        change(&prefs)
        cloudPrefs = prefs
        prefs.save(to: defaults)
    }

    /// Restores the model a thread used last, when it is still available.
    func select(modelID: String?) {
        guard let modelID, let model = models.first(where: { $0.id == modelID && $0.isInstalled }) else { return }
        select(model)
    }
}
