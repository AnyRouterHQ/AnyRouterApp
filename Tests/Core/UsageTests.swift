import Foundation
import Testing
@testable import AnyRouter

/// Agent v2 K1a: one usage type for every engine. A run of several rounds reports the sum of its rounds, and a count
/// only one round knows (a local engine's decoded tokens, a price) is kept rather than lost or turned into 0.
struct UsageTests {
    @Test func roundsAddUpFieldByField() {
        let first = Usage(input: 900, output: 20, cacheRead: 800, cacheWrite: 100, decoded: 900, reasoning: 5, costUSD: 1)
        let second = Usage(input: 1_200, output: 30, cacheRead: 1_000, cacheWrite: 200, decoded: 300, reasoning: 7, costUSD: 2)
        #expect(first + second == Usage(
            input: 2_100, output: 50, cacheRead: 1_800, cacheWrite: 300, decoded: 1_200, reasoning: 12, costUSD: 3))
    }

    @Test func aCountOnlyOneRoundKnowsIsKept() {
        let known = Usage(input: 10, output: 1, decoded: 4, costUSD: 1)
        let unknown = Usage(input: 5, output: 2)
        #expect((known + unknown).decoded == 4)
        #expect((unknown + known).decoded == 4)
        #expect((known + unknown).costUSD == 1)
        #expect((unknown + unknown).decoded == nil, "an engine that never says leaves it unknown, not 0")
        #expect((unknown + unknown).costUSD == nil)
    }

    /// Agent v2 U1: what a local engine decoded reaches the stored reply, the numerator of decoded/prompt.
    @MainActor @Test func theStoredReplyKeepsWhatTheEngineDecoded() {
        let model = ModelDescriptor(id: "gguf/a/b.gguf", source: .gguf, displayName: "B", capabilities: ["chat"], isInstalled: true)
        let m = ChatViewModel.finalMetadata(
            nil, tokens: Usage(input: 1_200, output: 30, decoded: 300), model: model, ttftMs: nil, totalMs: 1, nameOf: { _ in nil })
        #expect(m.promptTokens == 1_200 && m.completionTokens == 30 && m.decodedTokens == 300)
    }
}
