import Foundation

/// What the app does without a connection: which models and tools it skips, and what it tells the reader.
enum OfflineLogic {
    static let label = "Offline"
    static let pickerNote = "AnyRouter models need a connection."
    static let toolNote = "You are offline, so web tools were skipped."

    /// AnyRouter models run in the cloud. Apple and the downloaded models run on the device.
    static func needsNetwork(_ model: ModelDescriptor) -> Bool { model.source == .anyrouter }

    /// Apple Intelligence when it is ready, else the downloaded model that sorts first by name.
    static func suggestedModel(in models: [ModelDescriptor]) -> ModelDescriptor? {
        let usable = models.filter { $0.isInstalled && !needsNetwork($0) }
        if let apple = usable.first(where: { $0.source == .apple }) { return apple }
        return usable.min { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// What "Answer offline" does.
    enum Plan: Equatable, Sendable {
        /// A model that is already on this device.
        case use(ModelDescriptor)
        /// Nothing is installed: the smallest model that fits this device, to download.
        case download(LocalModelEntry)
        /// Nothing installed and nothing fits.
        case unavailable
    }

    /// An installed model first (Apple Intelligence, else the first by name). Otherwise the smallest catalog model that
    /// runs here, preferring one that runs well over one that is tight. `fit` comes from `FitPlanner`.
    static func plan(models: [ModelDescriptor], catalog: [LocalModelEntry]) -> Plan {
        if let installed = suggestedModel(in: models) { return .use(installed) }
        let candidates = catalog.filter { !$0.isDeprecated && $0.unavailableReason == nil && ($0.fit == .fits || $0.fit == .tight) }
        let runsWell = candidates.filter { $0.fit == .fits }
        let pool = runsWell.isEmpty ? candidates : runsWell
        guard let smallest = pool.min(by: { ($0.descriptor.sizeBytes ?? .max) < ($1.descriptor.sizeBytes ?? .max) }) else {
            return .unavailable
        }
        return .download(smallest)
    }

    static func downloadQuestion(_ entry: LocalModelEntry) -> String { "Download \(entry.descriptor.shortName)?" }

    static func downloadMessage(_ entry: LocalModelEntry) -> String {
        let size = entry.descriptor.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return "It answers without internet and fits this device." + (size.map { " Download size: \($0)." } ?? "")
    }

    static let nothingFitsMessage = "No model fits this device, so offline answers are not available."
    static func usingMessage(_ model: ModelDescriptor) -> String { "Using \(model.shortName), which runs on this device." }
    static func downloadingMessage(_ entry: LocalModelEntry) -> String {
        "Downloading \(entry.descriptor.shortName). Choose it in the model menu when it is ready."
    }

    /// Shown instead of a send that could only fail.
    static func modelMessage(for model: ModelDescriptor, suggestion: ModelDescriptor?) -> String {
        let base = "You are offline. \(model.shortName) needs a connection."
        guard let suggestion else { return base + " Download a model to chat without internet." }
        return base + " Switch to \(suggestion.shortName), which runs on this device."
    }

    /// A tool source's name in the composer menu: the services behind it need the connection.
    static func sourceTitle(_ title: String, needsNetwork: Bool, isOffline: Bool) -> String {
        needsNetwork && isOffline ? "\(title) · \(label)" : title
    }
}
