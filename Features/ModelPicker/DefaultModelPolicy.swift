import Foundation

/// Which model a chat uses when nobody picked one (or the pick can no longer be used).
///
/// Signed in to AnyRouter: the auto router. Otherwise Apple Intelligence when available,
/// else the first installed local model. "Signed in" means the cloud models are usable.
enum DefaultModelPolicy {
    static func resolve(saved: String?, models: [ModelDescriptor]) -> ModelDescriptor? {
        let usable = models.filter(\.isInstalled)
        if let saved, let match = usable.first(where: { $0.id == saved }) { return match }
        return usable.first { $0.id == ModelDescriptor.autoRouterID }
            ?? usable.first { $0.source == .apple }
            ?? usable.first { $0.source == .gguf || $0.source == .mlx }
            ?? usable.first { $0.source == .anyrouter && $0.id != ModelDescriptor.byokRouterID }
    }

    /// One line for Settings when the saved default cannot be used and the policy picked another model (or none).
    /// Nil when there is no saved default or it still works.
    static func fallbackNote(saved: String?, models: [ModelDescriptor]) -> String? {
        guard let saved else { return nil }
        let listed = models.first { $0.id == saved }
        if listed?.isInstalled == true { return nil }
        let name = listed?.shortName ?? (saved as NSString).lastPathComponent
        guard let fallback = resolve(saved: saved, models: models) else {
            return "Your default model, \(name), is not available. Choose another default."
        }
        return "Your default model, \(name), is not available. New chats use \(fallback.shortName)."
    }
}
