import XCTest

@testable import AnyRouter

final class AppleEngineTests: XCTestCase {
    func testSnapshotsBecomeAppendOnlyDeltas() {
        var tracker = SnapshotDeltaTracker()
        let snapshots = ["", "Hel", "Hello", "Hello", "Hello, wor", "Hello, world"]
        let deltas = snapshots.compactMap { tracker.delta(for: $0) }
        XCTAssertEqual(deltas, ["Hel", "lo", ", wor", "ld"])
        XCTAssertEqual(deltas.joined(), "Hello, world")
    }

    func testRewrittenSnapshotNeverRepeatsSentText() {
        var tracker = SnapshotDeltaTracker()
        XCTAssertEqual(tracker.delta(for: "Hello"), "Hello")
        // Model rewrote the start: only the new tail is appended.
        XCTAssertEqual(tracker.delta(for: "Jello there"), " there")
        XCTAssertNil(tracker.delta(for: "Jello"))
    }

    private func message(_ role: ChatMessage.Role, _ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: role, content: text, createdAt: Date())
    }

    func testSingleUserTurnIsSentAsIs() throws {
        let built = try ApplePrompt.build(messages: [message(.user, " hi ")], params: GenerationParams())
        XCTAssertEqual(built, ApplePrompt.Built(instructions: nil, prompt: "hi"))
    }

    func testSystemPromptAndSystemMessagesBecomeInstructions() throws {
        var params = GenerationParams()
        params.systemPrompt = "Be brief."
        let built = try ApplePrompt.build(
            messages: [message(.system, "Use English."), message(.user, "hi")], params: params)
        XCTAssertEqual(built.instructions, "Be brief.\n\nUse English.")
    }

    func testHistoryIsReplayedAsTranscript() throws {
        let built = try ApplePrompt.build(
            messages: [message(.user, "2+2?"), message(.assistant, "4"), message(.user, "and 3+3?")],
            params: GenerationParams())
        XCTAssertEqual(built.prompt, "User: 2+2?\n\nAssistant: 4\n\nUser: and 3+3?")
    }

    func testRequiresTrailingUserMessage() {
        XCTAssertThrowsError(try ApplePrompt.build(messages: [message(.assistant, "x")], params: GenerationParams()))
        XCTAssertThrowsError(try ApplePrompt.build(messages: [], params: GenerationParams()))
    }
}
