import Foundation
import Testing
@testable import AnyRouter

struct FitPlannerTests {
    // Qwen3 0.6B Q4_K_M: 28 layers x 8 KV heads x 128 dims x (K+V) x 2 bytes = 114,688 bytes per token.
    private let dense06 = ModelMemoryProfile(
        fileBytes: 396_705_472, fullKVBytesPerToken: 114_688, trainedContext: 40_960, activeFraction: nil)
    // Qwen3 4B Q4_K_M: 36 layers x 8 x 128 x 2 x 2 = 147,456 bytes per token.
    private let dense4 = ModelMemoryProfile(
        fileBytes: 2_497_281_312, fullKVBytesPerToken: 147_456, trainedContext: 40_960, activeFraction: nil)
    // A 26B mixture of experts, 128 experts with 8 active, a 6.88 GB file. 4 full-attention layers and 20 layers with a
    // 1024-token window, each layer 8 KV heads x 128 dims x 2 x 2 = 4096 bytes per token.
    private let moe = ModelMemoryProfile(
        fileBytes: 6_880_000_000, fullKVBytesPerToken: 4 * 4096, windowKVBytesPerToken: 20 * 4096, windowTokens: 1024,
        trainedContext: 1_000_000, activeFraction: ModelMemoryProfile.activeFraction(expertCount: 128, expertsUsed: 8))

    private func memory(_ gigabytes: Double) -> DeviceMemory {
        DeviceMemory(budgetBytes: Int64(gigabytes * 1_000_000_000), physicalBytes: 0)
    }

    private func verdict(_ profile: ModelMemoryProfile, _ gigabytes: Double) -> FitEstimate.Verdict {
        FitPlanner.estimate(profile, memory: memory(gigabytes)).verdict
    }

    // MARK: Device budget

    @Test func theBudgetIsTheProcessLimitMinusTheAppAndDoesNotShrinkWhileAModelIsLoaded() {
        // limit = used + available stays the same whether or not a 3 GB model is part of "used".
        let idle = MemorySnapshot(footprintBytes: 300_000_000, availableBytes: 5_700_000_000, physicalBytes: 8_000_000_000)
        let loaded = MemorySnapshot(footprintBytes: 3_300_000_000, availableBytes: 2_700_000_000, physicalBytes: 8_000_000_000)
        #expect(idle.deviceMemory.budgetBytes == 5_700_000_000)
        #expect(loaded.deviceMemory.budgetBytes == idle.deviceMemory.budgetBytes)
        #expect(idle.deviceMemory.physicalBytes == 8_000_000_000)
    }

    @Test func withoutAnAvailableReadingTheBudgetIsHalfOfRAMMinusTheApp() {
        let blind = MemorySnapshot(footprintBytes: 200_000_000, availableBytes: 0, physicalBytes: 8_000_000_000)
        #expect(blind.deviceMemory.budgetBytes == 3_700_000_000)
    }

    // MARK: KV cache

    @Test func kvGrowsWithContextForFullAttentionLayers() {
        #expect(dense4.kvBytes(context: 4096) == 147_456 * 4096)
        #expect(dense4.kvBytes(context: 0) == 0)
    }

    @Test func numbersFromAHostileCatalogCannotOverflowTheCacheMath() {
        let hostile = ModelMemoryProfile(
            fileBytes: 1_000_000_000, fullKVBytesPerToken: Int64.max, windowKVBytesPerToken: Int64.max,
            windowTokens: Int.max, trainedContext: Int.max, activeFraction: nil)
        #expect(hostile.kvBytes(context: Int.max) > 0)
        #expect(hostile.kvBytes(context: -5) == 0)
        #expect(FitPlanner.estimate(hostile, memory: memory(8)).verdict == .wontFit)
        let entry = CatalogEntry(repo: "org/m", format: .gguf, file: "m.gguf", title: "m", sizeBytes: Int64.max)
        #expect(entry.memoryProfile?.fileBytes == 1 << 50)
    }

    @Test func slidingWindowLayersStopGrowingAtTheirWindow() {
        let atWindow = moe.kvBytes(context: 1024)
        let beyond = moe.kvBytes(context: 8192)
        #expect(atWindow == 16_384 * 1024 + 81_920 * 1024)
        #expect(beyond == 16_384 * 8192 + 81_920 * 1024, "only the full-attention layers grow past the window")
        #expect(beyond < 81_920 * 8192, "a naive all-layers estimate would be far larger")
    }

    @Test func expertShareOfAMixtureOfExpertsFollowsTheRouting() {
        #expect(ModelMemoryProfile.activeFraction(expertCount: 128, expertsUsed: 8) == 0.119)
        #expect(ModelMemoryProfile.activeFraction(expertCount: 0, expertsUsed: 0) == nil)
        #expect(ModelMemoryProfile.activeFraction(expertCount: 8, expertsUsed: 9) == nil)
    }

    @Test func theFileSizeGuessIsMarkedAsAnEstimate() {
        let guess = ModelMemoryProfile.estimated(fileBytes: 2_000_000_000, trainedContext: 32_768)
        #expect(guess.isEstimated)
        #expect(guess.fullKVBytesPerToken == 160_000)
        #expect(FitPlanner.estimate(guess, memory: memory(8)).isEstimated)
    }

    // MARK: Verdicts on 6, 8 and 12 GB budgets

    @Test func aTinyDenseModelRunsWellEverywhereBigEnough() {
        for gigabytes in [3.0, 4.5, 6, 8, 12] { #expect(verdict(dense06, gigabytes) == .runsWell) }
        #expect(verdict(dense06, 1.5) == .tight(maxContext: 768, maxReply: 96))
    }

    @Test func aFourBillionDenseModelNeedsAboutFourPointFiveGigabytes() {
        #expect(verdict(dense4, 12) == .runsWell)
        #expect(verdict(dense4, 8) == .runsWell)
        #expect(verdict(dense4, 6) == .runsWell)
        #expect(verdict(dense4, 4.5) == .tight(maxContext: 6656, maxReply: 512))
        #expect(verdict(dense4, 3) == .wontFit)
    }

    @Test func theMixtureOfExpertsFileOnATwelveGigabyteBudgetRunsWellAndNeedsAboutEightPointOneGigabytes() {
        let estimate = FitPlanner.estimate(moe, memory: memory(12))
        #expect(estimate.verdict == .runsWell)
        #expect(estimate.context == 8192)
        #expect(estimate.totalBytes == 8_098_103_808)
        #expect(estimate.fileBytes + estimate.kvBytes + estimate.overheadBytes == estimate.totalBytes)
        #expect(!estimate.streamsFromStorage)
    }

    @Test func theMixtureOfExpertsFileOnAnEightGigabyteBudgetFitsOnlyWithAShortContext() {
        let estimate = FitPlanner.estimate(moe, memory: memory(8))
        #expect(estimate.verdict == .tight(maxContext: 2048, maxReply: 256))
        #expect(!estimate.streamsFromStorage, "the whole file still fits")
    }

    @Test func aMixtureOfExpertsFileLargerThanMemoryRunsFromMmapOnItsActiveExperts() {
        for gigabytes in [3.0, 4.5, 6] {
            let estimate = FitPlanner.estimate(moe, memory: memory(gigabytes))
            #expect(estimate.verdict == .tight(maxContext: 8192, maxReply: 512), "\(gigabytes) GB")
            #expect(estimate.streamsFromStorage)
            #expect(estimate.totalBytes > estimate.deviceBudgetBytes, "the file alone does not fit; only the active experts are resident")
        }
        #expect(verdict(moe, 1.5) == .wontFit, "even the active experts plus the overhead do not fit")
    }

    @Test func aDenseFileLargerThanMemoryNeverClaimsToFit() {
        let bigDense = ModelMemoryProfile(
            fileBytes: 6_880_000_000, fullKVBytesPerToken: 100_000, trainedContext: 8192, activeFraction: nil)
        #expect(verdict(bigDense, 6) == .wontFit)
        #expect(verdict(bigDense, 8) == .tight(maxContext: 1024, maxReply: 128))
    }

    // MARK: Boundaries

    @Test func runsWellStartsWhenFourThousandTokensFitWithFifteenPercentHeadroom() {
        let needed = dense4.fileBytes + dense4.kvBytes(context: 4096) + FitPlanner.overheadBytes
        #expect(needed == 4_101_261_088)
        let exact = DeviceMemory(budgetBytes: Int64((Double(needed) / FitPlanner.headroom).rounded(.up)), physicalBytes: 0)
        #expect(FitPlanner.estimate(dense4, memory: exact).verdict == .runsWell)
        let oneShort = DeviceMemory(budgetBytes: exact.budgetBytes - 10, physicalBytes: 0)
        guard case .tight = FitPlanner.estimate(dense4, memory: oneShort).verdict else {
            Issue.record("just under the headroom line must be tight")
            return
        }
    }

    @Test func wontFitStartsWhenTheMinimumContextDoesNotFit() {
        let minimum = dense4.fileBytes + dense4.kvBytes(context: FitPlanner.minContext) + FitPlanner.overheadBytes
        #expect(minimum == 3_572_778_784)
        #expect(FitPlanner.estimate(dense4, memory: DeviceMemory(budgetBytes: minimum, physicalBytes: 0)).verdict
            == .tight(maxContext: 512, maxReply: 64))
        #expect(FitPlanner.estimate(dense4, memory: DeviceMemory(budgetBytes: minimum - 1, physicalBytes: 0)).verdict == .wontFit)
    }

    @Test func replyLengthScalesWithContextBetweenSixtyFourAndFiveHundredTwelve() {
        #expect(FitPlanner.maxReply(forContext: 512) == 64)
        #expect(FitPlanner.maxReply(forContext: 1024) == 128)
        #expect(FitPlanner.maxReply(forContext: 4096) == 512)
        #expect(FitPlanner.maxReply(forContext: 8192) == 512)
    }

    // MARK: Context pick

    @Test func theContextIsTheLargestThatFitsInSteps() {
        let picked = FitPlanner.pickContext(dense4, memory: memory(4.5))
        #expect(picked == 6656)
        #expect(picked.map { $0 % FitPlanner.contextStep } == 0)
        let total = dense4.fileBytes + dense4.kvBytes(context: 6656) + FitPlanner.overheadBytes
        let next = dense4.fileBytes + dense4.kvBytes(context: 6656 + FitPlanner.contextStep) + FitPlanner.overheadBytes
        #expect(total <= 4_500_000_000 && next > 4_500_000_000)
    }

    @Test func theContextNeverExceedsTheModelsOwnLimitOrTheAppCap() {
        let short = ModelMemoryProfile(fileBytes: 400_000_000, fullKVBytesPerToken: 10_000, trainedContext: 2048, activeFraction: nil)
        #expect(FitPlanner.pickContext(short, memory: memory(12)) == 2048)
        #expect(FitPlanner.pickContext(dense06, memory: memory(12)) == FitPlanner.maxContext)
    }

    @Test func noContextIsPickedWhenTheModelWillNotFit() {
        #expect(FitPlanner.pickContext(dense4, memory: memory(3)) == nil)
    }

    @Test func aLargerBudgetNeverGivesASmallerContext() {
        var last = 0
        for tenths in stride(from: 15, through: 120, by: 5) {
            let context = FitPlanner.pickContext(moe, memory: memory(Double(tenths) / 10)) ?? 0
            #expect(context >= last, "budget \(tenths) tenths of a GB")
            last = context
        }
    }
}
