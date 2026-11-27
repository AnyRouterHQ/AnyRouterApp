import Foundation
import Testing
@testable import AnyRouter

struct FitTextTests {
    private func detail(
        _ verdict: ModelFit, needed: Int64 = 8_098_103_808, budget: Int64 = 5_700_000_000,
        context: Int = 1024, reply: Int = 128, streams: Bool = false, estimate: Bool = false
    ) -> FitDetail {
        FitDetail(verdict: verdict, neededBytes: needed, budgetBytes: budget, context: context, maxReply: reply,
                  streamsFromStorage: streams, isEstimate: estimate)
    }

    @Test func needsShowsOneDecimalGigabytesWithATilde() {
        #expect(FitText.needs(detail(.fits)) == "needs ~8.1 GB")
        #expect(FitText.needs(detail(.fits, needed: 620_000_000)) == "needs ~620 MB")
    }

    @Test func badgesNameTheVerdictAndTheDevice() {
        #expect(FitText.badge(detail(.fits), device: "iPhone") == "Runs well")
        #expect(FitText.badge(detail(.tight), device: "iPhone") == "May be slow")
        #expect(FitText.badge(detail(.wontFit), device: "iPhone") == "Too big for this iPhone")
        #expect(FitText.badge(detail(.wontFit), device: "iPad") == "Too big for this iPad")
        #expect(FitText.badge(detail(.unknown), device: "iPhone") == nil)
    }

    @Test func aTightModelExplainsItsContextAndReplyLimits() {
        #expect(FitText.explanation(detail(.tight), device: "iPhone")
            == "On this iPhone it supports a 1,024-token context and replies of up to 128 tokens.")
        let streamed = FitText.explanation(detail(.tight, streams: true), device: "iPhone")
        #expect(streamed?.hasSuffix("Weights stream from storage, so it is slower.") == true)
    }

    @Test func aModelThatRunsWellNeedsNoExplanation() {
        #expect(FitText.explanation(detail(.fits), device: "iPhone") == nil)
    }

    @Test func aTooBigModelSaysWhatItNeedsAndWhatTheDeviceCanGive() {
        #expect(FitText.explanation(detail(.wontFit), device: "iPhone")
            == "Needs ~8.1 GB · this iPhone has ~5.7 GB for apps")
    }

    @Test func onlyAModelThatWillNotFitWarnsBeforeDownloading() {
        #expect(FitText.downloadWarning(detail(.fits), sizeText: "2 GB", device: "iPhone") == nil)
        #expect(FitText.downloadWarning(detail(.tight), sizeText: "2 GB", device: "iPhone") == nil)
        #expect(FitText.downloadWarning(nil, sizeText: nil, device: "iPhone") == nil)
        let warning = FitText.downloadWarning(detail(.wontFit), sizeText: "6.88 GB", device: "iPhone")
        #expect(warning == "This model (6.88 GB) needs about 8.1 GB of memory. This iPhone can give about 5.7 GB, so it will not load.")
    }

    @Test func theStandardLimitNoteAppearsOnlyWhenTheEntitlementIsKnownToBeMissing() {
        #expect(FitText.memoryLimitNote(entitlementSigned: false)
            == "This install has the standard memory limit. TestFlight builds can load bigger models.")
        #expect(FitText.memoryLimitNote(entitlementSigned: true) == nil)
        #expect(FitText.memoryLimitNote(entitlementSigned: nil) == nil, "an unreadable signature must not scare anyone")
    }

    @Test func theMemoryLineShowsUseAndFreeSpace() {
        #expect(FitText.memoryLine(footprintBytes: 3_200_000_000, availableBytes: 2_100_000_000) == "App memory 3.2 GB, 2.1 GB free")
    }
}

@MainActor
struct MemoryMonitorTests {
    @Test func refreshReadsTheMemoryAndTheLoadedModel() async {
        let monitor = MemoryMonitor(
            read: { MemoryReadout(footprintBytes: 3_000_000_000, availableBytes: 2_000_000_000) },
            loaded: { "gguf/org/m/m.gguf" }, unload: {})
        await monitor.refresh()
        #expect(monitor.readout == MemoryReadout(footprintBytes: 3_000_000_000, availableBytes: 2_000_000_000))
        #expect(monitor.loadedModelID == "gguf/org/m/m.gguf")
    }

    @Test func unloadCallsTheEnginesAndThenShowsNothingLoaded() async {
        let state = UnloadState()
        let monitor = MemoryMonitor(
            read: { MemoryReadout(footprintBytes: 0, availableBytes: 0) },
            loaded: { await state.isLoaded ? "id" : nil },
            unload: { await state.unload() })
        await monitor.refresh()
        #expect(monitor.loadedModelID == "id")
        await monitor.unload()
        #expect(monitor.loadedModelID == nil)
        #expect(await state.unloadCalls == 1)
    }

    @Test func theInertMonitorHasNothingLoaded() async {
        let monitor = MemoryMonitor.inert()
        await monitor.refresh()
        #expect(monitor.loadedModelID == nil)
    }
}

private actor UnloadState {
    private(set) var isLoaded = true
    private(set) var unloadCalls = 0
    func unload() {
        isLoaded = false
        unloadCalls += 1
    }

    @Test func aFileTheInstallCannotMapExplainsTheAddressSpaceNotTheMemory() {
        var big = detail(.wontFit)
        big.mappableBytes = 4_200_000_000
        let reason = "This install can open files up to 4.2 GB at once. \(FitText.addressSpaceFix)"
        #expect(FitText.explanation(big, device: "iPhone") == reason)
        #expect(FitText.downloadWarning(big, sizeText: "6.9 GB", device: "iPhone") == "This model (6.9 GB) will not load. " + reason)
    }
}
