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
}
