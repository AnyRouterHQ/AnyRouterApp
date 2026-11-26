import XCTest

@testable import AnyRouter

/// Applies the Gemma 4 MLX chat template with the app's tokenizer loader. Needs no GPU and no weights, only the
/// tokenizer files, so it runs on the Simulator. It proves the jinja template parses and renders; generation stays device-only.
/// Skipped unless `ANYROUTER_SMOKE_MLX_TOKENIZER_DIR` is set.
final class MLXChatTemplateSmokeTests: XCTestCase {
    func testGemma4TemplateRendersAUserTurnAndOpensTheModelTurn() async throws {
        let path = SmokeEnv.mlxTokenizerDir
        try XCTSkipUnless(path != nil, "ANYROUTER_SMOKE_MLX_TOKENIZER_DIR is not set. This check runs only in model-smoke.yml.")
        let dir = try XCTUnwrap(path)
        let tokenizer = try await TransformersTokenizerLoader().load(from: URL(fileURLWithPath: dir))
        let ids = try tokenizer.applyChatTemplate(
            messages: [
                ["role": "system", "content": "Be brief."],
                ["role": "user", "content": "What is 2+2?"],
            ], tools: nil, additionalContext: nil)
        let text = tokenizer.decode(tokenIds: ids, skipSpecialTokens: false)
        SmokeReport.record("MLX Gemma 4 template", text)
        XCTAssertTrue(text.contains("<|turn>system\nBe brief.<turn|>"), "system turn missing in: \(text)")
        XCTAssertTrue(text.contains("<|turn>user\nWhat is 2+2?<turn|>"), "user turn missing in: \(text)")
        XCTAssertTrue(text.hasSuffix("<|turn>model\n"), "prompt must end by opening the model turn: \(text)")
    }
}
