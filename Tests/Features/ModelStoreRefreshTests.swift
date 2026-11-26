import Foundation
import Testing

@testable import AnyRouter

/// What an engine does on its next listing, changed by the test between refreshes.
final class ListingScript: @unchecked Sendable {
    private let lock = NSLock()
    private var failsRaw = false
    private var delayRaw: Duration = .zero
    var fails: Bool {
        get { lock.withLock { failsRaw } }
        set { lock.withLock { failsRaw = newValue } }
    }
    var delay: Duration {
        get { lock.withLock { delayRaw } }
        set { lock.withLock { delayRaw = newValue } }
    }
}

struct ScriptedListingEngine: ChatEngine {
    let source: ModelSource
    let models: [ModelDescriptor]
    let script: ListingScript

    func availableModels() async throws -> [ModelDescriptor] {
        if script.delay > .zero { try await Task.sleep(for: script.delay) }
        if script.fails { throw URLError(.timedOut) }
        return models
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class FailureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [String] = []
    func add(_ text: String) { lock.withLock { raw.append(text) } }
    var all: [String] { lock.withLock { raw } }
}

@MainActor
struct ModelStoreRefreshTests {
    private let cloud = testModel(id: "anyrouter/openai/gpt", source: .anyrouter)
    private let apple = testModel(id: "apple/foundation")

    private func make(
        cloudScript: ListingScript, log: FailureLog = FailureLog()
    ) -> ModelStore {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(source: .apple, models: [apple]))
        registry.register(ScriptedListingEngine(source: .anyrouter, models: [cloud], script: cloudScript))
        return ModelStore(registry: registry, defaults: testDefaults(), onLoadFailure: { log.add("\($0.rawValue): \($1)") })
    }

    @Test func aFailedRefreshKeepsTheCloudModelsAndSaysWhy() async {
        let script = ListingScript()
        let store = make(cloudScript: script)
        await store.refresh()
        #expect(store.models.map(\.id) == ["apple/foundation", "anyrouter/openai/gpt"])
        #expect(store.loadFailures.isEmpty)

        script.fails = true
        await store.refresh()
        #expect(store.models.map(\.id) == ["apple/foundation", "anyrouter/openai/gpt"], "a failed refresh must not empty the list")
        #expect(store.loadFailures[.anyrouter] == URLError(.timedOut).localizedDescription)

        script.fails = false
        await store.refresh()
        #expect(store.loadFailures.isEmpty, "the reason goes away when the list loads again")
    }

    @Test func aFirstLoadThatFailsLeavesNoCloudModelsAndTheReason() async {
        let script = ListingScript()
        script.fails = true
        let store = make(cloudScript: script)
        await store.refresh()
        #expect(store.models.map(\.id) == ["apple/foundation"])
        #expect(store.loadFailures[.anyrouter] != nil)
        #expect(store.hasLoaded)
    }

    @Test func aRefreshWaitingForTheCloudKeepsTheCloudModelsOnScreen() async {
        let script = ListingScript()
        let store = make(cloudScript: script)
        await store.refresh()

        script.delay = .milliseconds(400)
        let refreshing = Task { await store.refresh() }
        #expect(await waitUntil { store.isLoading })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.isLoading, "the cloud list is still on its way")
        #expect(store.models.contains { $0.id == cloud.id }, "the earlier cloud list stays until the new one lands")
        await refreshing.value
        #expect(store.models.count == 2)
    }

    @Test func aRefreshThatIsCancelledHalfWayDoesNotLoseTheCloudModels() async {
        let script = ListingScript()
        let store = make(cloudScript: script)
        await store.refresh()

        script.delay = .seconds(600)
        let refreshing = Task { await store.refresh() }
        #expect(await waitUntil { store.isLoading })
        try? await Task.sleep(for: .milliseconds(50))
        refreshing.cancel()
        await refreshing.value
        #expect(store.models.contains { $0.id == cloud.id })
    }

    @Test func eachNewFailureMessageIsReportedOnce() async {
        let script = ListingScript()
        let log = FailureLog()
        let store = make(cloudScript: script, log: log)
        script.fails = true
        await store.refresh()
        await store.refresh()
        #expect(log.all == ["anyrouter: \(URLError(.timedOut).localizedDescription)"])
    }

    @Test func theEmptyStateTellsALoadFromAFailureFromAListWithNothingUsable() {
        let locked = testModel(id: "anyrouter/openai/gpt", source: .anyrouter, installed: false)
        #expect(CloudEmptyReason.reason(models: [], failure: "x", isLoading: true) == .loading)
        #expect(CloudEmptyReason.reason(models: [], failure: "Timed out", isLoading: false) == .failed("Timed out"))
        #expect(CloudEmptyReason.reason(models: [locked], failure: nil, isLoading: false) == .nothingUsable(count: 1))
        #expect(CloudEmptyReason.reason(models: [apple], failure: nil, isLoading: false) == .none)
    }
}
