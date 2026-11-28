import Foundation

/// How a GGUF file loads on this device, from the fit estimate. Never a refusal: the estimate is a guess and the phone is
/// the evidence (the operator ran a model it called too big), so llama.cpp always gets to try, and a failure names its
/// own cause. Where the estimate doubts the model, the context is small and a mixture of experts streams from storage,
/// the only way a file bigger than the budget can run.
struct LlamaLoadPlan: Equatable, Sendable {
    var context: Int
    var streamsFromStorage: Bool
    /// The estimate said it will not fit; it loads anyway.
    var doubted: Bool

    static let doubtedContext = 2048

    static func make(_ estimate: FitEstimate, profile: ModelMemoryProfile) -> LlamaLoadPlan {
        let doubted = estimate.verdict == .wontFit
        return LlamaLoadPlan(
            context: doubted ? min(max(profile.trainedContext, FitPlanner.minContext), doubtedContext) : estimate.context,
            streamsFromStorage: estimate.streamsFromStorage || (doubted && profile.activeFraction != nil),
            doubted: doubted)
    }
}
