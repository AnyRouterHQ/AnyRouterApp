import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
private final class FakePathMonitor: PathMonitoring {
    private var update: (@MainActor @Sendable (Bool) -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0

    func start(_ update: @escaping @MainActor @Sendable (Bool) -> Void) {
        starts += 1
        self.update = update
    }

    func stop() { stops += 1 }

    func report(online: Bool) { update?(online) }
}

@MainActor
private final class Connection {
    var isOnline = true
}

@MainActor
struct OfflineTests {
    // MARK: Path monitor

    @Test func theStatusFollowsThePathMonitor() {
        let monitor = FakePathMonitor()
        let status = NetworkStatus(monitor: monitor)
        #expect(status.isOnline && !status.isOffline, "online until the monitor says otherwise")

        status.start()
        status.start()
        #expect(monitor.starts == 1, "a second start does not restart the monitor")

        monitor.report(online: false)
        #expect(status.isOffline)
        monitor.report(online: true)
        #expect(status.isOnline)
    }

    @Test func stoppingLetsTheMonitorStartAgain() {
        let monitor = FakePathMonitor()
        let status = NetworkStatus(monitor: monitor)
        status.start()
        status.stop()
        status.start()
        #expect(monitor.stops == 1 && monitor.starts == 2)
    }

    // MARK: Logic

    private let apple = RealisticModels.apple()
    private let cloud = RealisticModels.router()

    @Test func onlyAnyRouterModelsNeedTheNetwork() {
        #expect(OfflineLogic.needsNetwork(cloud))
        #expect(!OfflineLogic.needsNetwork(apple))
        #expect(!OfflineLogic.needsNetwork(testModel(id: "local/a", source: .gguf)))
        #expect(!OfflineLogic.needsNetwork(testModel(id: "local/b", source: .mlx)))
    }

    @Test func theSuggestionIsAppleThenTheFirstDownloadedModelByName() {
        let zed = testModel(id: "zed", source: .gguf)
        let alpha = testModel(id: "Alpha", source: .mlx)
        let missing = testModel(id: "aaa", source: .gguf, installed: false)
        #expect(OfflineLogic.suggestedModel(in: [cloud, zed, apple, alpha])?.id == AppleFoundationEngine.modelID)
        #expect(OfflineLogic.suggestedModel(in: [cloud, zed, alpha, missing])?.id == "Alpha")
        let appleOff = RealisticModels.apple(installed: false)
        #expect(OfflineLogic.suggestedModel(in: [appleOff, zed])?.id == "zed")
        #expect(OfflineLogic.suggestedModel(in: [cloud, missing, appleOff]) == nil)
    }

    @Test func theMessageNamesTheModelToSwitchTo() {
        let withSuggestion = OfflineLogic.modelMessage(for: cloud, suggestion: apple)
        #expect(withSuggestion == "You are offline. AnyRouter needs a connection. Switch to Apple Intelligence, which runs on this device.")
        #expect(OfflineLogic.modelMessage(for: cloud, suggestion: nil).hasSuffix("Download a model to chat without internet."))
    }

    @Test func offlineMarksTheServicesBehindASource() {
        #expect(OfflineLogic.sourceTitle("Exa", needsNetwork: true, isOffline: true) == "Exa · Offline")
        #expect(OfflineLogic.sourceTitle("Exa", needsNetwork: true, isOffline: false) == "Exa")
        #expect(OfflineLogic.sourceTitle("On this device", needsNetwork: false, isOffline: true) == "On this device")
    }

    // MARK: Tools

    private struct Refuses: ToolApproving {
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
    }

    private func registry() -> ToolRegistry {
        let defaults = testDefaults()
        let integrations = IntegrationsStore(
            defaults: defaults, credentials: FakeCredentialStore(),
            anyRouterToken: { nil }, session: MCPStubProtocol.session())
        return ToolRegistry(integrations: integrations, publicSources: ToolSourceCatalog.publicSources, defaults: defaults)
    }

    private func names(_ registry: ToolRegistry, offline: Bool) -> [String]? {
        registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: .apple, isOffline: offline))?.specs.map(\.name)
    }

    @Test func offlineLeavesOnlyTheToolsThatWorkOnTheDevice() {
        let registry = registry()
        #expect(names(registry, offline: false)?.contains("fetch_url") == true)
        #expect(names(registry, offline: false)?.contains("web_search_exa") == true)
        #expect(names(registry, offline: true) == ["current_date_time", "calculator"])
    }

    @Test func offlineSaysSoOnlyWhenAWebToolWasLeftOut() {
        let registry = registry()
        #expect(!registry.skipsOffline(ToolContext(modelSource: .apple)))
        #expect(registry.skipsOffline(ToolContext(modelSource: .apple, isOffline: true)))

        registry.setBuiltIn("fetch_url", enabled: false)
        for source in registry.publicSources { registry.setSource(source, on: false) }
        #expect(!registry.skipsOffline(ToolContext(modelSource: .apple, isOffline: true)))
        #expect(names(registry, offline: true) == ["current_date_time", "calculator"])
    }

    @Test func offlineWithNothingOnTheDeviceGivesNoHost() {
        let registry = registry()
        for name in ["fetch_url", "current_date_time", "calculator"] { registry.setBuiltIn(name, enabled: false) }
        #expect(names(registry, offline: true) == nil)
    }

    // MARK: Chat

    private func chat(connection: Connection, models list: [ModelDescriptor], tools: @escaping @MainActor (ToolContext) -> (any ToolHost)? = { _ in nil },
                      sawContext: @escaping @MainActor (ToolContext) -> Void = { _ in }) async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        for source in Set(list.map(\.source)) {
            registry.register(ScriptedEngine(source: source, models: list.filter { $0.source == source }, chunks: ["ok"]))
        }
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(
            thread: nil, context: context, registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { tools($0) },
            isOnline: { connection.isOnline },
            skipsToolsOffline: { sawContext($0); return $0.isOffline })
    }

    @Test func aCloudModelIsNotSentToWhileOffline() async throws {
        let connection = Connection()
        connection.isOnline = false
        let vm = try await chat(connection: connection, models: [cloud, apple])
        vm.choose(cloud)
        vm.input = "hello"
        #expect(vm.send() == nil)
        #expect(vm.messages.isEmpty)
        #expect(vm.input == "hello", "the text stays in the composer")
        #expect(vm.errorMessage?.contains("You are offline") == true)
        #expect(vm.errorMessage?.contains("Switch to Apple Intelligence") == true)
    }

    @Test func aDeviceModelAnswersWhileOffline() async throws {
        let connection = Connection()
        connection.isOnline = false
        let vm = try await chat(connection: connection, models: [cloud, apple])
        vm.choose(apple)
        vm.input = "hello"
        await vm.send()?.value
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        #expect(vm.errorMessage == nil)
    }

    @Test func regeneratingACloudReplyIsBlockedOnceTheConnectionIsGone() async throws {
        let connection = Connection()
        let vm = try await chat(connection: connection, models: [cloud, apple])
        vm.choose(cloud)
        vm.input = "hello"
        await vm.send()?.value
        #expect(vm.messages.count == 2)

        connection.isOnline = false
        #expect(vm.regenerate() == nil)
        #expect(vm.messages.count == 2, "the reply is kept")
        #expect(vm.errorMessage?.contains("You are offline") == true)
    }

    @Test func aSkippedWebToolIsSaidInTheChatAndForgottenOnceOnline() async throws {
        let connection = Connection()
        connection.isOnline = false
        let withTools = testModelWithTools()
        let box = ContextBox()
        let vm = try await chat(connection: connection, models: [withTools], tools: { _ in StubToolHost() },
                                sawContext: { box.values.append($0.isOffline) })
        vm.input = "what is new"
        await vm.send()?.value
        #expect(vm.offlineToolNote == OfflineLogic.toolNote)

        connection.isOnline = true
        vm.input = "and now"
        await vm.send()?.value
        #expect(vm.offlineToolNote == nil)
        #expect(box.values == [true, false], "each request told the registry whether the device was offline")
    }
}

@MainActor
private final class ContextBox {
    var values: [Bool] = []
}