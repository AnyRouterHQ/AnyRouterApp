import Foundation

extension ModelDescriptor {
    /// The model can emit reasoning, so the "Enable thinking" switch applies.
    var supportsThinking: Bool { capabilities.contains("reasoning") }
}

/// Text on the empty chat screen.
enum HomeLogic {
    static let greeting = "What can I help with?"
    static let noModelSubtitle = "Choose a model to start"

    static func subtitle(for model: ModelDescriptor?) -> String {
        guard let model else { return noModelSubtitle }
        switch model.source {
        case .anyrouter:
            return model.id.hasSuffix("/auto")
                ? "Using AnyRouter · picks the best model"
                : "Using AnyRouter · \(model.displayName)"
        case .apple: return "Using Apple Intelligence · on device"
        case .gguf, .mlx: return "Using \(model.displayName) · on device"
        }
    }
}
