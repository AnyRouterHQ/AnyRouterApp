import Foundation
import Testing
@testable import AnyRouter

struct MLXConversationTests {
    private func chat(_ role: ChatMessage.Role, _ text: String) -> ChatMessage {
        ChatMessage(role: role, content: text)
    }

    @Test func lastMessageBecomesThePromptAndEarlierTurnsBecomeHistory() throws {
        let result = try MLXConversation.split(
            messages: [chat(.user, "u1"), chat(.assistant, "a1"), chat(.user, "u2")], systemPrompt: nil)
        #expect(result.prompt == "u2")
        #expect(result.history == [PromptMessage(role: "user", content: "u1"), PromptMessage(role: "assistant", content: "a1")])
        #expect(result.instructions == nil)
    }

    @Test func systemMessagesAndTheParamsPromptBecomeInstructions() throws {
        let fromParams = try MLXConversation.split(messages: [chat(.user, "hi")], systemPrompt: "Be brief.")
        #expect(fromParams.instructions == "Be brief.")
        #expect(fromParams.history.isEmpty)

        let fromThread = try MLXConversation.split(
            messages: [chat(.system, "A"), chat(.system, "B"), chat(.user, "hi")], systemPrompt: "ignored")
        #expect(fromThread.instructions == "A\n\nB")
        #expect(fromThread.history.isEmpty, "system messages never count as history")
    }

    @Test func aChatWithNoUserTurnIsRefused() {
        #expect(throws: MLXError.emptyConversation) {
            _ = try MLXConversation.split(messages: [], systemPrompt: "sys")
        }
        #expect(throws: MLXError.emptyConversation) {
            _ = try MLXConversation.split(messages: [ChatMessage(role: .system, content: "only system")], systemPrompt: nil)
        }
    }
}

struct MLXEngineTests {
    private let entry = sampleMLX(repo: "org/model-4bit", title: "Tiny MLX")

    private func makeEngine(installed: Bool) throws -> MLXEngine {
        let storage = LocalModelStorage(root: makeTempDirectory())
        if installed {
            let url = storage.partialFileURL(forEntryID: entry.id, path: "config.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
            try ModelInstaller.verifyAndInstall(
                DownloadJobRecord(entry: entry, files: [HFFile(path: "config.json", size: 2)]), storage: storage)
        }
        let catalog = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        return MLXEngine(storage: storage, catalog: catalog)
    }

    private func drain(_ engine: MLXEngine) async throws {
        let model = entry.descriptor(isInstalled: true)
        for try await _ in engine.stream(model: model, messages: [ChatMessage(role: .user, content: "hi")], params: GenerationParams()) {}
    }

    @Test func engineListsOnlyInstalledMLXModels() async throws {
        let engine = try makeEngine(installed: true)
        let models = try await engine.availableModels()
        #expect(models.map(\.id) == [entry.id])
        #expect(models.first?.source == .mlx)
        #expect(engine.source == .mlx)
        #expect(try await makeEngine(installed: false).availableModels().isEmpty)
    }

    #if targetEnvironment(simulator)
    @Test func simulatorReportsMLXUnavailableWithAReasonTheUICanShow() async throws {
        guard case .unavailable(let reason) = MLXEngine.availability else {
            Issue.record("MLX must be unavailable in the Simulator")
            return
        }
        #expect(!reason.isEmpty)
        let engine = try makeEngine(installed: true)
        await #expect(throws: MLXError.unavailable(reason)) { try await drain(engine) }
    }
    #else
    @Test func deviceReportsMLXAvailable() {
        #expect(MLXEngine.availability == .available)
    }

    @Test func streamingAModelThatIsNotDownloadedFailsWithAClearError() async throws {
        let engine = try makeEngine(installed: false)
        await #expect(throws: MLXError.modelNotInstalled(entry.id)) { try await drain(engine) }
    }
    #endif
}
