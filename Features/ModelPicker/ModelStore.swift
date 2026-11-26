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
    private var selectedID: String?

    init(registry: EngineRegistry, defaults: UserDefaults = .standard, telemetry: any Telemetry = NoopTelemetry()) {
        self.registry = registry
        self.defaults = defaults
        self.telemetry = telemetry
        self.selectedID = defaults.string(forKey: Self.selectedKey)
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
        models = await registry.allModels()
        isLoading = false
        hasLoaded = true
    }

    /// Remembers the pick as the default for new chats.
    func select(_ model: ModelDescriptor) {
        selectedID = model.id
        defaults.set(model.id, forKey: Self.selectedKey)
        telemetry.track(.modelSelected(source: model.source))
    }

    /// Restores the model a thread used last, when it is still available.
    func select(modelID: String?) {
        guard let modelID, let model = models.first(where: { $0.id == modelID && $0.isInstalled }) else { return }
        select(model)
    }
}
