import Foundation

/// One group of models in the picker (Atomic groups its dropdown by provider).
struct PickerSection: Identifiable, Equatable {
    enum Kind: Int, Equatable { case apple, anyrouter, local }

    var kind: Kind
    var models: [ModelDescriptor]
    var id: Int { kind.rawValue }

    var title: String {
        switch kind {
        case .apple: "Apple Intelligence"
        case .anyrouter: "AnyRouter"
        case .local: "On this device"
        }
    }
}

enum ModelPickerLogic {
    /// Groups models by source in a fixed order: Apple, AnyRouter, local (GGUF and MLX).
    /// Local models that are not installed are left out (they live in the hub).
    /// The AnyRouter group is always present without a query so the sign-in prompt has a home.
    static func sections(models: [ModelDescriptor], query: String) -> [PickerSection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? models : models.filter {
            $0.displayName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.id.range(of: needle, options: .caseInsensitive) != nil
        }
        func pick(_ kinds: Set<ModelSource>) -> [ModelDescriptor] {
            matched.filter { kinds.contains($0.source) && ($0.source == .anyrouter || $0.isInstalled) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        let all: [PickerSection] = [
            PickerSection(kind: .apple, models: pick([.apple])),
            PickerSection(kind: .anyrouter, models: pick([.anyrouter])),
            PickerSection(kind: .local, models: pick([.gguf, .mlx])),
        ]
        return all.filter { !$0.models.isEmpty || (needle.isEmpty && $0.kind == .anyrouter) }
    }

    /// Short caption under a model name.
    static func subtitle(for model: ModelDescriptor) -> String {
        switch model.source {
        case .apple: return "On device"
        case .anyrouter: return "Cloud"
        case .gguf, .mlx:
            let kind = model.source == .gguf ? "GGUF" : "MLX"
            guard let size = model.sizeBytes else { return kind }
            return "\(kind) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
    }
}
