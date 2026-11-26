import Foundation
@testable import AnyRouter

/// Models built the way the app lists them, so a test that asserts a message asserts what a person reads.
enum RealisticModels {
    /// What `AppleFoundationEngine` lists: the wire id the app uses and the name the picker shows.
    static func apple(installed: Bool = true) -> ModelDescriptor {
        ModelDescriptor(
            id: AppleFoundationEngine.modelID, source: .apple, displayName: "Apple Intelligence", contextLength: 4096,
            capabilities: ["chat"], sizeBytes: nil, isInstalled: installed)
    }

    /// AnyRouter's own router, whose short name is "AnyRouter".
    static func router() -> ModelDescriptor {
        testModel(id: ModelDescriptor.autoRouterID, source: .anyrouter)
    }
}
