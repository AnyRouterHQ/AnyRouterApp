import Foundation
import Testing
@testable import AnyRouter

/// The streamed tier: a mixture-of-experts file too big for the app's memory limit runs from mmap, but only on a device
/// whose RAM can cache the whole file. The Inkling 2 Mini 1-bit build is the case it was built for.
struct StreamedFitTests {
    // Numbers from catalog/dev-models.json (written by scripts/catalog-add.sh from the GGUF header).
    private let inkling = ModelMemoryProfile(
        fileBytes: 6_881_463_904, fullKVBytesPerToken: 16_384, windowKVBytesPerToken: 81_920, windowTokens: 1024,
        trainedContext: 1_048_576, activeFraction: 0.119, lazyBytes: 260_527_104)

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

    @Test func fromTwelveGigabytesInklingStreamsWithTheFullContextTheChatWindowAssumes() {
        let cases: [(DeviceClass, MemoryLimitKind)] = [(.gb12, .standard), (.gb16, .standard)]
        for (deviceClass, kind) in cases {
            let estimate = FitPlanner.estimate(inkling, memory: deviceClass.memory(kind))
            #expect(estimate.verdict == .streamed(maxContext: 8192, maxReply: 512), "\(deviceClass.rawValue) GB \(kind)")
            #expect(estimate.streamsFromStorage)
            #expect(estimate.streamsOn == nil)
            #expect(FitPlanner.pickContext(inkling, memory: deviceClass.memory(kind)) == 8192)
        }
    }

    @Test func aRealTwelveGigabytePhoneReadingStreamsInklingInsteadOfRefusingIt() {
        // What the system reports on an iPhone 18 Pro with the standard limit: RAM a little under 12 GB, 3.5 GB limit
        // minus the app's own use, and an address space that holds the 6.4 GiB file (7.4 GiB largest mapping).
        let memory = DeviceMemory(budgetBytes: 3_200_000_000, physicalBytes: 11_500_000_000, mappableBytes: 7_946_000_000)
        let estimate = FitPlanner.estimate(inkling, memory: memory)
        #expect(estimate.verdict == .streamed(maxContext: 8192, maxReply: 512))
        #expect(!estimate.cannotMap)
    }

    @Test func theStreamedContextIsTheWindowTheChatCompactsAgainst() {
        let model = ModelDescriptor(
            id: "inkling", source: .gguf, displayName: "Inkling", contextLength: 1_048_576, capabilities: ["chat"],
            sizeBytes: nil, isInstalled: true)
        let planned = FitPlanner.pickContext(inkling, memory: DeviceClass.gb12.memory(.standard))
        #expect(planned == CompactionLogic.window(for: model), "a smaller loaded context would trim the prompt before compaction runs")
    }

    @Test func aTwelveGigabytePhoneWithTheIncreasedLimitHoldsTheFileInMemory() {
        // 8.1 GB for a model: the file, 8,192 tokens of KV cache and 1 GB of buffers fit, without the 15% headroom.
        let estimate = FitPlanner.estimate(inkling, memory: DeviceClass.gb12.memory(.increased))
        #expect(estimate.verdict == .tight(maxContext: 8192, maxReply: 512))
        #expect(!estimate.streamsFromStorage)
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

    @Test func aFileBiggerThanTheMappableAddressSpaceDoesNotLoadWhateverTheMemory() {
        var memory = DeviceClass.gb16.memory(.increased)
        memory.mappableBytes = 6_000_000_000
        let estimate = FitPlanner.estimate(inkling, memory: memory)
        #expect(estimate.verdict == .wontFit, "llama.cpp maps the file in one piece: memory to spare does not help")
        #expect(estimate.cannotMap)
        memory.mappableBytes = 8_000_000_000
        #expect(FitPlanner.estimate(inkling, memory: memory).verdict == .runsWell)
        #expect(!FitPlanner.estimate(inkling, memory: memory).cannotMap)
        memory.mappableBytes = nil
        #expect(FitPlanner.estimate(inkling, memory: memory).verdict == .runsWell, "not measured: no check")
    }

    @Test func photosNeedAddressSpaceForTheModelFileOnly() throws {
        var profile = inkling
        profile.projectorBytes = 345_911_008
        var memory = DeviceClass.gb16.memory(.increased)
        // More than the model file, less than the file, the projector and the image encoder together.
        memory.mappableBytes = 7_000_000_000
        let estimate = try #require(FitPlanner.imageInputEstimate(profile, memory: memory))
        #expect(!estimate.cannotMap, "the projector is read into memory, not mapped")
    }

    @Test func theAddressSpaceProbeFindsTheLargestStepTheSystemAccepts() {
        #expect(MemoryReading.largestReservable(upTo: 64, step: 4) { $0 <= 37 } == 36)
        #expect(MemoryReading.largestReservable(upTo: 64, step: 4) { _ in false } == 0)
        #expect(MemoryReading.largestReservable(upTo: 64, step: 4) { _ in true } == 64)
        #expect(MemoryReading.canReserve(1 << 20))
        #expect(!MemoryReading.canReserve(1 << 62), "no process can reserve 4 EB of address space")
        #expect(MemoryReading.largestMappableBytes() == nil, "the Simulator has the Mac's address space: no check there")
        #expect(DeviceMemory.current(mappable: true).mappableBytes == nil)
    }
}
