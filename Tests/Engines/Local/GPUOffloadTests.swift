import Foundation
import Testing
@testable import AnyRouter

struct GPUOffloadTests {
    @Test func aModelThatFitsTheGPUWorkingSetOffloadsEveryLayerAndTheOutput() {
        #expect(GPUOffload.layers(blockCount: 36, fileBytes: 2_500_000_000, gpuBudgetBytes: 5_000_000_000) == 37)
    }

    @Test func aLargerModelKeepsOnlyTheShareThatFitsOnTheGPU() {
        // Weights may use 75% of 4 GB = 3 GB. A 6 GB file puts half of its 24 layers there.
        #expect(GPUOffload.layers(blockCount: 24, fileBytes: 6_000_000_000, gpuBudgetBytes: 4_000_000_000) == 12)
    }

    @Test func aModelFarLargerThanTheGPUBudgetOffloadsNothing() {
        #expect(GPUOffload.layers(blockCount: 24, fileBytes: 600_000_000_000, gpuBudgetBytes: 4_000_000_000) == 0)
    }

    @Test func unknownLimitsOrShapesOffloadEverything() {
        #expect(GPUOffload.layers(blockCount: 24, fileBytes: 6_000_000_000, gpuBudgetBytes: nil) == 25)
        #expect(GPUOffload.layers(blockCount: 0, fileBytes: 6_000_000_000, gpuBudgetBytes: 1) == 1)
        #expect(GPUOffload.layers(blockCount: 24, fileBytes: 0, gpuBudgetBytes: 1) == 25)
    }
}
