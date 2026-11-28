import Foundation

/// What Private Cloud Compute (Apple Intelligence on Apple's servers, iOS 27) can report, in the app's own values, so the
/// picker row, its reason and the error words are tested without the iOS 27 SDK.
/// API: developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel
enum ApplePCCStatus: Equatable, Sendable {
    /// `contextSize` is the model's own, read from the framework; nil when it did not say.
    case available(contextSize: Int?)
    /// `.unavailable(.deviceNotEligible)`: the device does not support Apple Intelligence.
    case deviceNotEligible
    /// `.unavailable(.systemNotReady)`: Apple Intelligence is off or still setting up, or PCC is not serving yet.
    case systemNotReady
    /// Unavailable for a reason this build does not know.
    case unavailable
    /// iOS before 27, or an app built without the iOS 27 SDK.
    case needsNewerSystem
    /// This install is not signed with `com.apple.developer.private-cloud-compute`.
    case notEntitled
}

/// Reads the real model. The app's reader (`ApplePCCReader`) needs the iOS 27 SDK; tests pass a stub.
protocol ApplePCCProbing: Sendable {
    func status() async -> ApplePCCStatus
}

/// The Private Cloud Compute model as the picker and the chat see it. It is a second model of the Apple engine, not an
/// engine of its own: same tools and prompt assembly, with the context the framework reports.
enum ApplePCCLogic {
    static let modelID = "apple/pcc"
    static let displayName = "Apple Intelligence (Cloud)"
    static let detail = "Free · Private Cloud Compute"
    static let entitlementKey = "com.apple.developer.private-cloud-compute"

    /// A readable signature without the entitlement wins over what the framework says: the app may not call it.
    static func status(framework: ApplePCCStatus, entitled: Bool?) -> ApplePCCStatus {
        entitled == false ? .notEntitled : framework
    }

    /// The reason under Not available, or nil when it can be used.
    static func reason(_ status: ApplePCCStatus) -> String? {
        switch status {
        case .available: nil
        case .deviceNotEligible: "This device does not support Apple Intelligence"
        case .systemNotReady: "Turn on Apple Intelligence, or wait until it finishes setting up"
        case .unavailable: "Private Cloud Compute is not available right now"
        case .needsNewerSystem: "Needs iOS 27"
        case .notEntitled: "This build is not yet allowed to use Private Cloud Compute"
        }
    }

    static func descriptor(_ status: ApplePCCStatus) -> ModelDescriptor {
        var contextSize: Int?
        if case .available(let size) = status { contextSize = size }
        let ready = reason(status) == nil
        return ModelDescriptor(
            id: modelID, source: .apple, displayName: displayName, contextLength: contextSize,
            capabilities: ready ? ["chat", "tools"] : ["chat"], sizeBytes: nil, isInstalled: ready, summary: reason(status))
    }

    /// "32K context" for the picker row, nil while the size is unknown.
    static func contextText(_ tokens: Int?) -> String? {
        tokens.map { "\($0 / 1000)K context" }
    }

    /// What a request can fail with, from `PrivateCloudComputeLanguageModel.Error`.
    enum Failure: Equatable, Sendable {
        case quotaLimitReached
        case networkFailure
        case serviceUnavailable
    }

    static func text(_ failure: Failure) -> String {
        switch failure {
        case .quotaLimitReached: "You reached today's Private Cloud Compute limit. It resets tomorrow; the on-device model still works."
        case .networkFailure: "Private Cloud Compute needs the internet. Try again, or use the on-device model."
        case .serviceUnavailable: "Private Cloud Compute is busy. Try again in a moment."
        }
    }
}
