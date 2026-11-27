import Foundation
import Testing
@testable import AnyRouter

/// The streamed tier: a mixture-of-experts file too big for the app's memory limit runs from mmap, but only on a device
/// whose RAM can cache the whole file. Inkling 2 Mini IQ1_S is the case it was built for.
struct StreamedFitTests {
    // Numbers from catalog/dev-models.json (written by scripts/catalog-add.sh from the GGUF header).
    private let inkling = ModelMemoryProfile(
        fileBytes: 7_764_293_056, fullKVBytesPerToken: 16_384, windowKVBytesPerToken: 81_920, windowTokens: 1024,
        trainedContext: 1_048_576, activeFraction: 0.119, lazyBytes: 246_053_376)

    @Test func inklingNeedsATwelveGigabyteDeviceToStream() {
        #expect(FitPlanner.streamingClass(inkling) == .gb12)
    }

    @Test func belowTwelveGigabytesInklingDoesNotLoadAndNamesTheRAMItNeeds() {
        for kind in MemoryLimitKind.allCases {
            for deviceClass in [DeviceClass.gb4, .gb6, .gb8] {
                let estimate = FitPlanner.estimate(inkling, memory: deviceClass.memory(kind))
                #expect(estimate.verdict == .wontFit, "\(deviceClass.rawValue) GB \(kind)")
                #expect(estimate.streamsOn == .gb12, "\(deviceClass.rawValue) GB \(kind)")
            }
        }
    }

    @Test func fromTwelveGigabytesInklingStreamsWithAFourThousandTokenContext() {
        let cases: [(DeviceClass, MemoryLimitKind)] = [(.gb12, .standard), (.gb12, .increased), (.gb16, .standard)]
        for (deviceClass, kind) in cases {
            let estimate = FitPlanner.estimate(inkling, memory: deviceClass.memory(kind))
            #expect(estimate.verdict == .streamed(maxContext: 4096, maxReply: 512), "\(deviceClass.rawValue) GB \(kind)")
            #expect(estimate.streamsFromStorage)
            #expect(estimate.streamsOn == nil)
            #expect(FitPlanner.pickContext(inkling, memory: deviceClass.memory(kind)) == 4096)
        }
    }

    @Test func anIPadProWithTheIncreasedLimitHoldsTheWholeFile() {
        let estimate = FitPlanner.estimate(inkling, memory: DeviceClass.gb16.memory(.increased))
        #expect(estimate.verdict == .runsWell)
        #expect(!estimate.streamsFromStorage)
    }

    @Test func whereRAMCannotCacheTheFileAModelThatFitsWithAShortContextStaysInMemory() {
        // A budget big enough for the whole file with a short context, on an 8 GB device: no streaming, no RAM note.
        let memory = DeviceMemory(budgetBytes: 9_000_000_000, physicalBytes: 7_500_000_000)
        let estimate = FitPlanner.estimate(inkling, memory: memory)
        guard case .tight = estimate.verdict else {
            Issue.record("expected a tight in-memory fit, got \(estimate.verdict)")
            return
        }
        #expect(!estimate.streamsFromStorage)
        #expect(estimate.streamsOn == nil)
    }

    @Test func aFileNoDeviceCanCacheGivesNoRAMToAskFor() {
        var huge = inkling
        huge.fileBytes = 20_000_000_000
        #expect(FitPlanner.streamingClass(huge) == nil)
        let estimate = FitPlanner.estimate(huge, memory: DeviceClass.gb16.memory(.standard))
        #expect(estimate.verdict == .wontFit)
        #expect(estimate.streamsOn == nil)
    }

    @Test func aDenseModelNeverStreams() {
        let dense = ModelMemoryProfile(fileBytes: 6_000_000_000, fullKVBytesPerToken: 100_000, trainedContext: 8192, activeFraction: nil)
        let estimate = FitPlanner.estimate(dense, memory: DeviceClass.gb16.memory(.standard))
        #expect(estimate.verdict == .wontFit)
        #expect(estimate.streamsOn == nil, "only a mixture of experts can stream")
    }
}
