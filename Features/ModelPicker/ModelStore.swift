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
    private var selectedID: String?

    init(registry: EngineRegistry, defaults: UserDefaults = .standard, telemetry: any Telemetry = NoopTelemetry()) {
        self.registry = registry
        self.defaults = defaults
        self.telemetry = telemetry
        self.selectedID = defaults.string(forKey: Self.selectedKey)
    }

    /// The chosen model when it is still usable, else the first usable one.
    var selected: ModelDescriptor? {
        let usable = models.filter(\.isInstalled)
        return usable.first { $0.id == selectedID } ?? usable.first
    }

    func refresh() async {
        isLoading = true
        models = await registry.allModels()
        isLoading = false
    }

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
