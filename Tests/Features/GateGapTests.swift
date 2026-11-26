import Foundation
import Testing
@testable import AnyRouter

struct IntegrationsLogicGapTests {
    @Test func everyProblemHasAMessageTheUserCanActOn() {
        let all: [IntegrationsLogic.URLProblem] = [.empty, .notHTTPS, .invalid, .duplicate]
        let texts = all.compactMap(\.errorDescription)
        #expect(texts.count == 4)
        #expect(Set(texts).count == 4)
        #expect(IntegrationsLogic.URLProblem.empty.errorDescription == "Enter the server URL.")
        #expect(IntegrationsLogic.URLProblem.duplicate.errorDescription == "This server is already added.")
    }

    @Test(arguments: ["http://localhost:8787/mcp", "http://127.0.0.1:9/mcp", "http://[::1]:9/mcp"])
    func plainHTTPIsAllowedOnlyForThisDevice(input: String) {
        #expect((try? IntegrationsLogic.validate(input).get()) != nil)
    }

    @Test(arguments: ["https://", "ftp://example.com", "http://192.168.1.5/mcp"])
    func addressesWithoutAUsableHostOrSchemeAreRejected(input: String) {
        #expect((try? IntegrationsLogic.validate(input).get()) == nil)
    }

    @Test func suggestedNameDropsWwwAndMcpButKeepsShortHosts() throws {
        func name(_ text: String) throws -> String { IntegrationsLogic.defaultName(for: try #require(URL(string: text))) }
        #expect(try name("https://www.example.com/x") == "example.com")
        #expect(try name("https://mcp.io/x") == "mcp.io")
        #expect(try name("mailto:someone@example.com") == "Server")
    }
}

@MainActor
struct IntegrationsStoreGapTests {
    private struct Deny: ToolApproving {
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
    }

    private func makeStore(token: String? = "tok") -> IntegrationsStore {
        IntegrationsStore(
            defaults: testDefaults(), credentials: FakeCredentialStore(),
            anyRouterToken: { token }, session: MCPStubProtocol.session())
    }

    private func addServer(_ store: IntegrationsStore) throws -> MCPServer {
        let url = MCPStubProtocol.register(standardMCPHandler())
        return try store.addServer(name: "Tools", urlString: url.absoluteString, token: "")
    }

    @Test func aSignInServerUsesTheSignInTokenAndAsksToSignInAgainWhenItIsRejected() async {
        let store = makeStore(token: "tok")
        let rejected = MCPServer(id: "ar", name: "AR", url: MCPStubProtocol.register { _ in StubResponse(status: 401, body: "{}") },
                                 auth: .anyRouterSignIn)
        await store.refresh(rejected)
        #expect(store.state(for: rejected).status == .needsSignIn)

        let accepted = MCPServer(id: "ar2", name: "AR", url: MCPStubProtocol.register(standardMCPHandler()), auth: .anyRouterSignIn)
        await store.refresh(accepted)
        #expect(store.state(for: accepted).status == .connected)
        #expect(MCPStubProtocol.requests(for: accepted.url).last?.header("Authorization") == "Bearer tok")
    }

    @Test func refreshAllVisitsEveryServer() async throws {
        let store = makeStore(token: nil)
        let server = try addServer(store)
        await store.refreshAll()
        #expect(store.state(for: .anyRouter).status == .needsSignIn)
        #expect(store.state(for: server).status == .connected)
    }

    @Test func aCancelledRefreshGoesBackToIdleWithoutAnError() async throws {
        let store = makeStore()
        let server = try addServer(store)
        let task = Task { await store.refresh(server) }
        task.cancel()
        await task.value
        #expect(store.state(for: server).status == .idle)
    }

    @Test func theClientForAServerIsCreatedOnceAndReused() async throws {
        let store = makeStore()
        let server = try addServer(store)
        let first = store.client(for: server)
        let second = store.client(for: server)
        #expect(first === second)
    }

    @Test func aToolHostExistsOnlyWhenAConnectedServerHasAToolTurnedOn() async throws {
        let store = makeStore()
        let server = try addServer(store)
        #expect(store.makeToolHost(approver: Deny()) == nil)
        await store.refresh(server)
        let host = try #require(store.makeToolHost(approver: Deny()))
        #expect(host.specs.count == 5)
        for tool in store.state(for: server).tools { store.setEnabled(false, tool: tool, on: server) }
        #expect(store.makeToolHost(approver: Deny()) == nil)
    }
}

@MainActor
struct PresetStoreGapTests {
    private func sample() -> [PromptPreset] {
        [PromptPreset(id: "b1", title: "B", prompt: "p", category: .learn, symbol: "sparkles")]
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString).json")
    }

    @Test func aBundleWithoutPresetsIsALoudError() {
        let empty = Bundle(path: makeTempDirectory().path)
        #expect(throws: (any Error).self) { try PresetStore.bundled(bundle: empty) }
    }

    @Test func theDefaultFileLivesInApplicationSupport() {
        #expect(PresetStore.defaultURL.lastPathComponent == "presets.json")
        #expect(!PresetStore(fileURL: tempURL()).builtIns.isEmpty)
    }

    @Test func updatingAnUnknownPresetChangesNothing() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: sample())
        store.update(PromptPreset(id: "ghost", title: "x", prompt: "y", category: .code, symbol: "sparkles"))
        #expect(store.custom.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFileThatCannotBeWrittenIsReportedAndRecoversLater() throws {
        let blocker = makeTempDirectory().appendingPathComponent("blocker")
        try Data("file, not folder".utf8).write(to: blocker)
        let store = PresetStore(fileURL: blocker.appendingPathComponent("sub/presets.json"), builtIns: sample())
        store.add(title: "Mine", prompt: "p", category: .plan)
        #expect(store.saveError?.hasPrefix("Could not save presets:") == true)
        #expect(store.custom.count == 1, "the preset stays in memory")
    }

    @Test func aBrokenSavedFileIsIgnoredAndHiddenBuiltInsAreTracked() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("garbage".utf8).write(to: url)
        let store = PresetStore(fileURL: url, builtIns: sample())
        #expect(store.custom.isEmpty)
        #expect(!store.hasHiddenBuiltIns)
        store.setBuiltInHidden("b1", hidden: true)
        #expect(store.hasHiddenBuiltIns)
        #expect(store.all.isEmpty)
        store.setBuiltInHidden("b1", hidden: false)
        #expect(store.all.map(\.id) == ["b1"])
        let added = store.add(title: "Mine", prompt: "p", category: .write)
        #expect(store.customIDs == [added.id])
    }
}

struct SettingsLogicGapTests {
    @Test func versionTextShowsTheBuildAndOptionallyTheCommit() {
        #expect(SettingsLogic.versionText(version: "0.1.0", build: "42") == "0.1.0 (42)")
        #expect(SettingsLogic.versionText(version: "0.1.0", build: "42", commit: "") == "0.1.0 (42)")
        #expect(SettingsLogic.versionText(version: "0.1.0", build: "42", commit: "abc1234") == "0.1.0 (42) · abc1234")
    }

    @Test func diagnosticsListPlainFactsOnly() {
        let text = SettingsLogic.diagnostics(version: "1.2", build: "3", system: "26.0")
        #expect(text.hasPrefix("AnyRouter 1.2 (3)"))
        #expect(text.hasSuffix("\niOS 26.0"))
    }

    @Test func theRunningAppReportsItsOwnVersionBuildAndCommit() {
        #expect(!SettingsLogic.appVersion.isEmpty)
        #expect(!SettingsLogic.appBuild.isEmpty)
        #expect(!SettingsLogic.appCommit.isEmpty)
        #expect(SettingsLogic.diagnosticsTapCount == 7)
    }
}
