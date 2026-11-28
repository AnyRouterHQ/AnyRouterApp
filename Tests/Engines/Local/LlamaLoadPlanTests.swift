import Foundation
import Testing
@testable import AnyRouter

/// The engine never refuses a model because of the fit estimate (the operator ran Inkling 2 Mini on a phone the estimate
/// called too small). A doubted model still gets a plan: a small context, and streaming when it is a mixture of experts.
struct LlamaLoadPlanTests {
    private let tiny = DeviceMemory(budgetBytes: 500_000_000, physicalBytes: 4_000_000_000)

    @Test func aModelTheEstimateCallsTooBigStillGetsAPlanWithASmallContext() {
        let dense = ModelMemoryProfile(fileBytes: 5_000_000_000, fullKVBytesPerToken: 131_072, trainedContext: 32_768, activeFraction: nil)
        let estimate = FitPlanner.estimate(dense, memory: tiny)
        #expect(estimate.verdict == .wontFit)
        let plan = LlamaLoadPlan.make(estimate, profile: dense)
        #expect(plan == LlamaLoadPlan(context: 2048, streamsFromStorage: false, doubted: true))
    }

    @Test func aDoubtedMixtureOfExpertsStreamsFromStorage() {
        let moe = ModelMemoryProfile(fileBytes: 6_881_463_904, fullKVBytesPerToken: 16_384, trainedContext: 1_048_576, activeFraction: 0.119)
        let plan = LlamaLoadPlan.make(FitPlanner.estimate(moe, memory: tiny), profile: moe)
        #expect(plan.doubted && plan.streamsFromStorage && plan.context == 2048)
    }

    @Test func aShortTrainedContextIsKeptAndNeverBelowTheMinimum() {
        let small = ModelMemoryProfile(fileBytes: 5_000_000_000, fullKVBytesPerToken: 131_072, trainedContext: 1024, activeFraction: nil)
        #expect(LlamaLoadPlan.make(FitPlanner.estimate(small, memory: tiny), profile: small).context == 1024)
        let unknown = ModelMemoryProfile(fileBytes: 5_000_000_000, fullKVBytesPerToken: 131_072, trainedContext: 0, activeFraction: nil)
        #expect(LlamaLoadPlan.make(FitPlanner.estimate(unknown, memory: tiny), profile: unknown).context == FitPlanner.minContext)
    }

    @Test func aModelThatFitsLoadsWithTheEstimatesContext() {
        let roomy = DeviceMemory(budgetBytes: 8_000_000_000, physicalBytes: 16_000_000_000)
        let small = ModelMemoryProfile(fileBytes: 500_000_000, fullKVBytesPerToken: 49_152, trainedContext: 32_768, activeFraction: nil)
        let estimate = FitPlanner.estimate(small, memory: roomy)
        #expect(LlamaLoadPlan.make(estimate, profile: small) == LlamaLoadPlan(context: estimate.context, streamsFromStorage: false, doubted: false))
    }

    /// The address-space probe no longer decides anything in the engine: a file bigger than it still gets a plan.
    @Test func aFileBiggerThanTheMappingProbeIsNotRefused() {
        var memory = DeviceMemory(budgetBytes: 20_000_000_000, physicalBytes: 16_000_000_000)
        memory.mappableBytes = 4_200_000_000
        let moe = ModelMemoryProfile(fileBytes: 6_881_463_904, fullKVBytesPerToken: 16_384, trainedContext: 8192, activeFraction: 0.119)
        let plan = LlamaLoadPlan.make(FitPlanner.estimate(moe, memory: memory), profile: moe)
        #expect(plan.doubted && plan.streamsFromStorage, "even a probe that says no leaves llama.cpp to try")
    }
}
