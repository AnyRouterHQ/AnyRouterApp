import Foundation
import Testing
@testable import AnyRouter

/// The footer's speed is the reply's own output over its own generation time: a subagent's tokens and the time the
/// reply waited on tools are left out (operator-visible bug after S1).
struct ReplySpeedTests {
    @Test func timeSpentInToolsIsNotGenerationTime() {
        var metadata = ResponseMetadata(completionTokens: 100)
        metadata.ttftMs = 1_000
        metadata.totalMs = 13_000
        #expect(metadata.tokensPerSecond == 100.0 / 12.0)
        metadata.toolMs = 10_000
        #expect(metadata.tokensPerSecond == 100.0 / 2.0, "ten seconds waiting on a subagent do not count")
        metadata.toolMs = 12_000
        #expect(metadata.tokensPerSecond == nil, "no generation time left, no speed")
        metadata.toolMs = 11_990
        #expect(metadata.tokensPerSecond == nil, "under 50 ms is too short to say")
    }

    @Test func aSubagentsTokensShowUnderItsOwnRowsAndNotInTheSpeed() {
        let cloud = ModelDescriptor(id: "anyrouter/auto", source: .anyrouter, displayName: "Auto", contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        let metadata = SubagentLogic.adding((600, 60), to: ResponseMetadata(promptTokens: 2_200, completionTokens: 90))
        var timed = metadata
        timed.ttftMs = 500
        timed.totalMs = 3_500
        #expect(timed.tokensPerSecond == 30, "90 own tokens in 3 s, not 150")
        let details = ReplyDetails.make(
            requestedName: "Auto", requestedID: cloud.id, metadata: timed, steps: [], reasoningMs: nil)
        let rows = details.sections.flatMap(\.rows)
        #expect(rows.contains { $0.label == "Output" && $0.value == "90" })
        #expect(rows.contains { $0.label == "Subagent input" && $0.value == "600" })
        #expect(rows.contains { $0.label == "Subagent output" && $0.value == "60" })
    }
}
