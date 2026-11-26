import FoundationModels
import XCTest

@testable import AnyRouter

/// Reports whether Apple Foundation Models can run here, and chats only if it can.
/// GitHub runners almost never have it. Then the test is skipped with the reason, never faked as a pass.
final class AppleFoundationSmokeTests: XCTestCase {
    func testReportsAvailabilityAndChatsWhenAvailable() async throws {
        try XCTSkipUnless(SmokeEnv.enabled, "ANYROUTER_SMOKE is not set. The Apple check runs only in model-smoke.yml.")
        if let note = AppleFoundationEngine.unavailabilityNote() {
            let reason = "unavailable: \(note) [\(SystemLanguageModel.default.availability)]"
            SmokeReport.record("Apple Foundation Models", "SKIPPED, \(reason)")
            throw XCTSkip("Apple Foundation Models \(reason)")
        }

        let engine = AppleFoundationEngine()
        let models = try await engine.availableModels()
        let model = try XCTUnwrap(models.first)
        var text = ""
        var done = false
        let messages = [ChatMessage(role: .user, content: "Reply with the single word: ok")]
        do {
            for try await delta in engine.stream(model: model, messages: messages, params: GenerationParams()) {
                switch delta {
                case .text(let piece): text += piece
                case .done: done = true
                case .usage, .toolCall, .toolResult, .metadata: break
                }
            }
        } catch {
            // Runners report "available" but have no model assets. That is an environment limit, not a pass.
            let detail = String(describing: error)
            guard detail.contains("ModelManagerError") else { throw error }
            let reason = "availability says available, but generation failed because the model assets are missing: ModelManagerError 1026"
            SmokeReport.record("Apple Foundation Models", "SKIPPED, \(reason)")
            throw XCTSkip("Apple Foundation Models: \(reason)")
        }
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(done)
        SmokeReport.record("Apple Foundation Models", "available, answered: \(text.prefix(80))")
    }
}
