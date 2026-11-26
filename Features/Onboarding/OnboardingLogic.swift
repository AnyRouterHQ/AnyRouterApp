import Foundation

enum OnboardingLogic {
    enum Choice: Hashable, Sendable { case apple, local, cloud }

    /// Largest local model we offer first: at most this big, so a first download stays quick.
    static let recommendedMaxBytes: Int64 = 1_500_000_000

    /// First catalog entry that fits the device and is small; else the smallest one that fits at all.
    static func recommendedLocal(in catalog: [LocalModelEntry]) -> LocalModelEntry? {
        let usable = catalog.filter { $0.fit != .wontFit && $0.unavailableReason == nil }
        if let small = usable.first(where: { ($0.descriptor.sizeBytes ?? .max) <= recommendedMaxBytes }) { return small }
        return usable.min { ($0.descriptor.sizeBytes ?? .max) < ($1.descriptor.sizeBytes ?? .max) }
    }

    /// Whether the person can leave onboarding with this choice working right now.
    static func canFinish(choice: Choice?, appleAvailable: Bool, localState: DownloadState, signedIn: Bool) -> Bool {
        switch choice {
        case .apple: appleAvailable
        case .local: localState == .installed
        case .cloud: signedIn
        case nil: false
        }
    }

    /// The model to select on finish, by id.
    static func modelID(for choice: Choice, models: [ModelDescriptor], local: LocalModelEntry?) -> String? {
        switch choice {
        case .apple: models.first { $0.source == .apple && $0.isInstalled }?.id
        case .local: local?.id
        case .cloud: models.first { $0.source == .anyrouter }?.id
        }
    }
}
