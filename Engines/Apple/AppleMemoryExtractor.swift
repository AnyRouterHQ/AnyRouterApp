import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, asked for what the user's message says about the user (agent design 2.3, unit M6). One guided
/// generation call that returns a list of at most three statements. It cannot run on the CI Simulator (no model there), so
/// it is on the on-device eval list; the rules around it are unit tested with a fake (MemoryExtractionLogic).
struct AppleMemoryExtractor: MemoryExtracting {
    func statements(in message: String) async -> [String] {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return [] }
        let session = LanguageModelSession(instructions: MemoryExtractionLogic.instructions)
        let options = GenerationOptions(temperature: 0.1, maximumResponseTokens: 160)
        do {
            let response = try await session.respond(
                to: MemoryExtractionLogic.prompt(for: message), generating: ExtractedStatements.self, options: options)
            return response.content.statements
        } catch {
            return []
        }
        #else
        return []
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct ExtractedStatements {
    @Guide(description: "What the user said about themselves, each a short first-person sentence. Empty when nothing lasting.", .maximumCount(3))
    var statements: [String]
}
#endif
