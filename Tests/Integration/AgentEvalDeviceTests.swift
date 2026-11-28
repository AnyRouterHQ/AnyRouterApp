import XCTest

@testable import AnyRouter

/// The on-device list for LA11 (like `AppleToolEvalTests`): the same fixture on Apple's model and on an installed MLX model.
/// Opt in with `RUN_DEVICE_EVALS=1` in the test process (for xcodebuild: `TEST_RUNNER_RUN_DEVICE_EVALS=1`). Both skip
/// everywhere else, with the reason. Apple runs its own tool loop, so its rounds are not counted.
final class AgentEvalDeviceTests: XCTestCase {
    private func requireOptIn() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_DEVICE_EVALS"] == "1",
            "On-device evals are opt-in: set RUN_DEVICE_EVALS=1 and run on a device.")
    }

    func testAppleModelRunsTheToolSet() async throws {
        try requireOptIn()
        if let note = AppleFoundationEngine.unavailabilityNote() {
            throw XCTSkip("Apple Foundation Models is unavailable on this host (\(note)). Run it on a device with Apple Intelligence.")
        }
        let engine = AppleFoundationEngine()
        let model = try XCTUnwrap(try await engine.availableModels().first)
        let result = try await AgentToolEvalRunner.runSet(
            try AgentEvalFixtures.toolCases(), engine: engine, model: model, rounds: nil, label: "Apple Foundation Models", section: "toolsApple")
        XCTAssertFalse(result.cases.isEmpty, "no case ran inside the time cap")
    }

    func testInstalledMLXModelRunsTheToolSet() async throws {
        try requireOptIn()
        guard case .available = MLXEngine.availability else { throw XCTSkip("MLX needs a device with a GPU, not the Simulator.") }
        let mlx = MLXEngine()
        let installed = try await mlx.availableModels().filter { $0.isInstalled && LocalToolFormat.detect(for: $0) != nil }
        let model = try XCTUnwrap(installed.first, "no installed MLX model has a tool format (Qwen, Gemma or Llama 3)")
        let counter = EvalRoundCounter()
        let engine = LocalToolEngine(wrapping: EvalCountingEngine(base: mlx, counter: counter), isEnabled: { true })
        let result = try await AgentToolEvalRunner.runSet(
            try AgentEvalFixtures.toolCases(), engine: engine, model: model, rounds: counter, label: "MLX, \(model.displayName)", section: "toolsMLX")
        XCTAssertFalse(result.cases.isEmpty, "no case ran inside the time cap")
    }
}
