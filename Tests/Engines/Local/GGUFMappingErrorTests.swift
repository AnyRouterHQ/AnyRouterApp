import Foundation
import Testing
@testable import AnyRouter

/// A file the install cannot map in one piece is refused with the reason, not left to llama.cpp's "failed to load model".
struct GGUFMappingErrorTests {
    @Test func theMessageNamesTheFileItsSizeAndHowMuchThisInstallCanOpen() {
        let error = GGUFMappingError(name: "Inkling-2-Mini-AD-IQ1_S.gguf", fileBytes: 6_881_463_904, mappableBytes: 4_200_000_000)
        let text = error.errorDescription ?? ""
        #expect(text.hasPrefix("Could not load Inkling-2-Mini-AD-IQ1_S.gguf (6.9 GB). "))
        #expect(text.contains("files up to 4.2 GB at once"))
        #expect(text.hasSuffix(FitText.addressSpaceFix))
    }

    @Test func theRefusalMatchesTheFitCheckThatTheHubUses() {
        // The hub and the engine ask the same question: the file against what one mapping can take.
        var memory = DeviceMemory(budgetBytes: 20_000_000_000, physicalBytes: 16_000_000_000)
        let profile = ModelMemoryProfile(fileBytes: 6_881_463_904, fullKVBytesPerToken: 16_384, trainedContext: 8192, activeFraction: 0.119)
        memory.mappableBytes = 4_200_000_000
        #expect(FitPlanner.estimate(profile, memory: memory).cannotMap)
        memory.mappableBytes = 8_000_000_000
        #expect(!FitPlanner.estimate(profile, memory: memory).cannotMap)
    }
}
