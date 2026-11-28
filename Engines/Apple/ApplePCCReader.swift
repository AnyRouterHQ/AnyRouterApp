import Foundation
import FoundationModels

/// The real Private Cloud Compute model. The code that names it compiles only against the iOS 27 SDK (APPLE_PCC_SDK is set
/// per SDK in project.yml), so the iOS 26 SDK builds stay as they are and report `.needsNewerSystem`.
/// Docs: developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute
struct ApplePCCReader: ApplePCCProbing {
    func status() async -> ApplePCCStatus {
        let signed = Bundle.main.executableURL.flatMap { MemoryEntitlement.signedEntitlements(executable: $0) }
        let entitled = signed.map { ($0[ApplePCCLogic.entitlementKey] as? Bool) == true }
        #if APPLE_PCC_SDK
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            let framework: ApplePCCStatus
            switch model.availability {
            case .available: framework = .available(contextSize: try? await model.contextSize)
            case .unavailable(.deviceNotEligible): framework = .deviceNotEligible
            case .unavailable(.systemNotReady): framework = .systemNotReady
            case .unavailable: framework = .unavailable
            }
            return ApplePCCLogic.status(framework: framework, entitled: entitled)
        }
        #endif
        _ = entitled
        return .needsNewerSystem
    }

    #if APPLE_PCC_SDK
    @available(iOS 27.0, *)
    static func session(tools: [any Tool], instructions: String?) -> LanguageModelSession {
        let model = PrivateCloudComputeLanguageModel()
        return instructions.map { LanguageModelSession(model: model, tools: tools, instructions: $0) }
            ?? LanguageModelSession(model: model, tools: tools)
    }

    @available(iOS 27.0, *)
    static func failure(_ error: any Error) -> ApplePCCLogic.Failure? {
        guard let error = error as? PrivateCloudComputeLanguageModel.Error else { return nil }
        switch error {
        case .quotaLimitReached: return .quotaLimitReached
        case .networkFailure: return .networkFailure
        case .serviceUnavailable: return .serviceUnavailable
        @unknown default: return .serviceUnavailable
        }
    }
    #endif
}
