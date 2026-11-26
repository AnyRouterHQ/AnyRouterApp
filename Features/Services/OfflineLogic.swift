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
