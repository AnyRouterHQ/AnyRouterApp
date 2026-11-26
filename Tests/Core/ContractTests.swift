import Foundation
import Testing
@testable import AnyRouter

struct ContractTests {
    @Test func modelDescriptorRoundTripsThroughJSON() throws {
        let m = ModelDescriptor(id: "mlx/org/repo", source: .mlx, displayName: "Repo", contextLength: 4096,
                                capabilities: ["chat", "tools"], sizeBytes: 123, isInstalled: false)
        let back = try JSONDecoder().decode(ModelDescriptor.self, from: JSONEncoder().encode(m))
        #expect(back == m)
    }

    @Test func generationParamsDefaultsMatchContract() {
        let p = GenerationParams()
        #expect(p.temperature == 0.7)
        #expect(p.topP == 0.95)
        #expect(p.maxTokens == nil)
        #expect(p.systemPrompt == nil)
    }

    @Test func roleRawValuesAreStableBecauseTheyArePersisted() {
        #expect(ChatMessage.Role.allCases_rawValues == ["system", "user", "assistant"])
        #expect(ModelSource.anyrouter.rawValue == "anyrouter")
    }
}

private extension ChatMessage.Role {
    static var allCases_rawValues: [String] { [Self.system, .user, .assistant].map(\.rawValue) }
}
