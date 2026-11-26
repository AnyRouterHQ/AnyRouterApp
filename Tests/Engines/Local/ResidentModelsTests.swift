import Foundation
import Testing
@testable import AnyRouter

private struct FakeWeights: Sendable, Equatable { var name: String }
private struct OtherWeights: Sendable, Equatable { var name: String }
private struct LoadFailure: Error {}

/// Counts loads and can hold one back until the test lets it go.
private final class Loader: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    private let started: AsyncStream<Void>.Continuation
    let startedEvents: AsyncStream<Void>
    private let proceed: AsyncStream<Void>.Continuation
    private let proceedEvents: AsyncStream<Void>
    private let holdsBack: Bool

    init(holdsBack: Bool = false) {
        let starts = AsyncStream<Void>.makeStream()
        startedEvents = starts.stream
        started = starts.continuation
        let proceeds = AsyncStream<Void>.makeStream()
        proceedEvents = proceeds.stream
        proceed = proceeds.continuation
        self.holdsBack = holdsBack
    }

    var count: Int { lock.withLock { loads } }

    /// Waits until a load has begun.
    func waitForStart() async {
        for await _ in startedEvents { return }
    }

    func letLoadFinish() { proceed.yield() }

    func load(_ name: String, failing: Bool = false) async throws -> FakeWeights {
        lock.withLock { loads += 1 }
        started.yield()
        if holdsBack { for await _ in proceedEvents { break } }
        if failing { throw LoadFailure() }
        return FakeWeights(name: name)
    }
}

/// The cache of loaded weights that both local engines share. One test for each rule of
/// formal/LocalModelLifecycle.tla that the cache carries.
struct ResidentModelsTests {
    private func weights(
        _ models: ResidentModels, _ name: String, installedAt: Date? = nil, using loader: Loader
    ) async throws -> FakeWeights {
        try await models.weights(
            FakeWeights.self, at: "/models/\(name)", id: name, installedAt: installedAt, source: .gguf
        ) { try await loader.load(name) }
    }

    @Test func aSecondRequestForTheSameModelReusesTheWeights() async throws {
        let models = ResidentModels()
        let loader = Loader()
        _ = try await weights(models, "a", using: loader)
        let again = try await weights(models, "a", using: loader)
        #expect(again == FakeWeights(name: "a"))
        #expect(loader.count == 1)
        #expect(await models.loadedID == "a")
    }

    @Test func aDownloadToTheSamePathReplacesTheWeights() async throws {
        let models = ResidentModels()
        let loader = Loader()
        _ = try await weights(models, "a", installedAt: Date(timeIntervalSince1970: 1), using: loader)
        _ = try await weights(models, "a", installedAt: Date(timeIntervalSince1970: 2), using: loader)
        #expect(loader.count == 2)
    }

    @Test func loadingAnotherModelFreesTheFirstEvenFromTheOtherEngine() async throws {
        let models = ResidentModels()
        let loader = Loader()
        _ = try await weights(models, "a", using: loader)
        let other = try await models.weights(
            OtherWeights.self, at: "/mlx/b", id: "b", source: .mlx
        ) { OtherWeights(name: "b") }
        #expect(other == OtherWeights(name: "b"))
        #expect(await models.loadedID == "b", "one loaded model for every local engine")
    }

    @Test func aRequestDuringALoadJoinsItInsteadOfLoadingTwice() async throws {
        let models = ResidentModels()
        let loader = Loader(holdsBack: true)
        let first = Task { try await weights(models, "a", using: loader) }
        await loader.waitForStart()
        let second = Task { try await weights(models, "a", using: loader) }
        loader.letLoadFinish()
        let one = try await first.value
        let two = try await second.value
        #expect(one == FakeWeights(name: "a"))
        #expect(two == FakeWeights(name: "a"))
        #expect(loader.count == 1)
    }

    @Test func anUnloadDuringALoadMeansTheWeightsAreNotKept() async throws {
        let models = ResidentModels()
        let loader = Loader(holdsBack: true)
        let call = Task { try await weights(models, "a", using: loader) }
        await loader.waitForStart()
        await models.unload() // a memory warning while the model loads
        loader.letLoadFinish()
        let got = try await call.value
        #expect(got == FakeWeights(name: "a"), "the chat that asked still gets its model")
        #expect(await models.loadedID == nil, "but nothing keeps it once the chat is over")
    }

    @Test func deletingAModelDuringItsLoadMeansTheWeightsAreNotKept() async throws {
        let models = ResidentModels()
        let loader = Loader(holdsBack: true)
        let call = Task { try await weights(models, "a", using: loader) }
        await loader.waitForStart()
        await models.unload(ifID: "a")
        loader.letLoadFinish()
        _ = try await call.value
        #expect(await models.loadedID == nil)
    }

    @Test func deletingAnotherModelDuringALoadKeepsTheLoad() async throws {
        let models = ResidentModels()
        let loader = Loader(holdsBack: true)
        let call = Task { try await weights(models, "a", using: loader) }
        await loader.waitForStart()
        await models.unload(ifID: "b")
        loader.letLoadFinish()
        _ = try await call.value
        #expect(await models.loadedID == "a")
    }

    @Test func aFailedLoadLeavesNothingBehindAndCanBeTriedAgain() async throws {
        let models = ResidentModels()
        let loader = Loader()
        await #expect(throws: LoadFailure.self) {
            try await models.weights(FakeWeights.self, at: "/models/a", id: "a", source: .gguf) {
                try await loader.load("a", failing: true)
            }
        }
        #expect(await models.loadedID == nil)
        _ = try await weights(models, "a", using: loader)
        #expect(await models.loadedID == "a")
        #expect(loader.count == 2)
    }
}

struct GenerationGateTests {
    @Test func releaseHandsTheGateToTheNextWaiterWithoutFreeingIt() async {
        let gate = GenerationGate()
        await gate.acquire()
        let waiter = Task { await gate.acquire() }
        while await gate.waitingCount == 0 { await Task.yield() }
        await gate.release()
        await waiter.value
        #expect(await !gate.tryAcquire(), "the waiter holds the gate; a warm-up must not take it")
        await gate.release()
        #expect(await gate.tryAcquire(), "free once the last holder is done")
    }
}
