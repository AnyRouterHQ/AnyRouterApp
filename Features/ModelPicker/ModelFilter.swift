import Foundation

/// Filters of the AnyRouter tab. Pure data, so every combination is tested without a view.
/// The default is the "nothing chosen" state: only models the user can route to are shown.
struct ModelFilter: Equatable, Codable, Sendable {
    enum MaxPrice: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, upTo1, upTo5

        var id: String { rawValue }
        /// USD per 1M input tokens, nil for no limit.
        var limit: Decimal? {
            switch self {
            case .any: nil
            case .upTo1: 1
            case .upTo5: 5
            }
        }
        var title: String {
            switch self {
            case .any: "Any"
            case .upTo1: "Up to $1"
            case .upTo5: "Up to $5"
            }
        }
    }

    static let longContextTokens = 128_000

    var freeOnly = false
    var vision = false
    var tools = false
    var reasoning = false
    var longContext = false
    var maxInputPrice: MaxPrice = .any
    /// Provider prefixes of the wire id ("openai", "anthropic"). Empty means all.
    var providers: Set<String> = []
    /// On by default. A search still finds models that need a key.
    var hideNeedsKey = true

    /// How many settings differ from the default. Shown on the filter button.
    var activeCount: Int {
        [freeOnly, vision, tools, reasoning, longContext, maxInputPrice != .any, !providers.isEmpty, !hideNeedsKey]
            .filter { $0 }.count
    }

    var isActive: Bool { activeCount > 0 }

    /// Everything except `hideNeedsKey`, which depends on whether the user is searching.
    func matches(_ model: ModelDescriptor) -> Bool {
        if freeOnly && model.cloud?.pricing.isFree != true { return false }
        if vision && model.cloud?.supportsVision != true { return false }
        if tools && !model.capabilities.contains("tools") { return false }
        if reasoning && model.cloud?.supportsReasoning != true { return false }
        if longContext && (model.contextLength ?? 0) < Self.longContextTokens { return false }
        if let limit = maxInputPrice.limit {
            guard let pricing = model.cloud?.pricing else { return false }
            if !pricing.isFree {
                guard let input = pricing.input, input <= limit else { return false }
            }
        }
        if !providers.isEmpty && !providers.contains(Self.provider(of: model)) { return false }
        return true
    }

    static func provider(of model: ModelDescriptor) -> String { model.cloudProvider ?? "other" }

    /// Providers that have at least one model in the list, A to Z by display name.
    static func providers(in models: [ModelDescriptor]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for model in models where model.source == .anyrouter { counts[provider(of: model), default: 0] += 1 }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted {
                ModelPickerLogic.providerTitle($0.name).localizedCaseInsensitiveCompare(ModelPickerLogic.providerTitle($1.name))
                    == .orderedAscending
            }
    }
}

/// Filters of the Local tab.
struct LocalFilter: Equatable, Codable, Sendable {
    enum Engine: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, gguf, mlx, apple

        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any"
            case .gguf: "GGUF"
            case .mlx: "MLX"
            case .apple: "Apple Intelligence"
            }
        }
    }

    var engine: Engine = .any
    /// Only models that run well on this device. Models without a fit check pass.
    var fitsOnly = false
    /// Hides models that cannot be used now, like Apple Intelligence when it is off.
    var hideUnavailable = false

    var activeCount: Int { [engine != .any, fitsOnly, hideUnavailable].filter { $0 }.count }
    var isActive: Bool { activeCount > 0 }

    /// `fit` is the device-fit verdict from the hub, nil when there is none.
    func matches(_ model: ModelDescriptor, fit: ModelFit?) -> Bool {
        switch engine {
        case .any: break
        case .gguf: if model.source != .gguf { return false }
        case .mlx: if model.source != .mlx { return false }
        case .apple: if model.source != .apple { return false }
        }
        if fitsOnly, let fit, fit != .fits, fit != .unknown { return false }
        if hideUnavailable && !model.isInstalled { return false }
        return true
    }
}

/// Remembers the filters of each tab.
struct PickerFilterStore {
    static let cloudKey = "picker.filter.anyrouter"
    static let localKey = "picker.filter.local"

    let defaults: UserDefaults

    /// Demo runs (screenshots, UI tests) use the demo suite, which is wiped at launch, so a filter set in
    /// one test does not leak into the next.
    static var standardDefaults: UserDefaults {
        DemoData.isEnabled ? (UserDefaults(suiteName: "dev.anyrouter.app.demo") ?? .standard) : .standard
    }

    func cloud() -> ModelFilter { load(Self.cloudKey) ?? ModelFilter() }
    func local() -> LocalFilter { load(Self.localKey) ?? LocalFilter() }
    func save(cloud filter: ModelFilter) { store(filter, Self.cloudKey) }
    func save(local filter: LocalFilter) { store(filter, Self.localKey) }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
