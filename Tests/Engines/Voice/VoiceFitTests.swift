import Testing
@testable import AnyRouter

struct VoiceFitTests {
    private func memory(_ deviceClass: DeviceClass, _ kind: MemoryLimitKind = .standard) -> DeviceMemory { deviceClass.memory(kind) }

    @Test func theSystemEngineAlwaysFits() {
        #expect(VoiceFit.verdict(.system(.stt), memory: memory(.gb4)) == .system)
    }

    @Test func aModelNeedsHalfTheBudgetToRunWellAndThreeQuartersToLoad() {
        let device = DeviceMemory(budgetBytes: 1_000_000_000, physicalBytes: 4_000_000_000)
        func verdict(resident: Int64) -> VoiceFit.Verdict {
            var model = VoiceFixtures.model("m")
            model.residentBytes = resident
            return VoiceFit.verdict(model, memory: device)
        }
        #expect(verdict(resident: 500_000_000) == .runsWell)
        #expect(verdict(resident: 500_000_001) == .tight)
        #expect(verdict(resident: 750_000_000) == .tight)
        #expect(verdict(resident: 750_000_001) == .wontFit)
    }

    @Test func withoutAMeasuredFootprintTheDownloadIsScaled() {
        let model = VoiceFixtures.model("m", size: 100_000_000)
        #expect(VoiceFit.residentBytes(model) == 220_000_000)
    }

    @Test func theRecommendedWhisperGrowsWithTheDevice() throws {
        let models = try BundledVoiceCatalog.load()
        func pick(_ deviceClass: DeviceClass, _ kind: MemoryLimitKind = .standard) -> String? {
            VoiceFit.recommended(models, kind: .stt, memory: memory(deviceClass, kind))?.id
        }
        let orders = [DeviceClass.gb4, .gb6, .gb8, .gb12, .gb16].map { pick($0) }
        let ranks = orders.map { id in models.first { $0.id == id }?.order ?? 0 }
        #expect(ranks == ranks.sorted(), "a bigger device never gets a smaller recommendation")
        #expect(pick(.gb8) == "whisper-large-v3-turbo")
        #expect(pick(.gb4) != "whisper-large-v3-turbo")
        for deviceClass in DeviceClass.allCases {
            let chosen = try #require(VoiceFit.recommended(models, kind: .stt, memory: memory(deviceClass)))
            #expect(VoiceFit.verdict(chosen, memory: memory(deviceClass)) == .runsWell)
        }
    }

    @Test func noModelOfAKindMeansNoRecommendation() throws {
        let speechToTextOnly = try BundledVoiceCatalog.load().filter { $0.kind == .stt }
        #expect(VoiceFit.recommended(speechToTextOnly, kind: .tts, memory: memory(.gb16)) == nil)
        #expect(VoiceFit.recommended([], kind: .stt, memory: memory(.gb16)) == nil)
    }

    @Test func everyVerdictHasATitle() {
        let verdicts: [VoiceFit.Verdict] = [.system, .runsWell, .tight, .wontFit]
        #expect(Set(verdicts.map(\.title)).count == 4)
    }
}
