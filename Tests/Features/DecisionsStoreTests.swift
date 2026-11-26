import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct DecisionGate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream<Void>.makeStream() }

    func wait() async {
        for await _ in stream { return }
    }

    func open() {
        continuation.yield()
        continuation.finish()
    }
}

final class FakeDecisionsService: DecisionsService, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [DecisionRequest] = []
    var models: Result<[DecisionModel], Error> = .success([])
    var outcome: Result<DecisionResult, Error> = .success(FakeDecisionsService.result)
    var gate: DecisionGate?

    static let result = DecisionResult(
        model: "anyrouter/decision",
        answers: [DecisionAnswer(
            id: "q1", prompt: "Urgent?",
            outcome: .answered(.init(headline: "Yes", probability: 0.9, options: [.init(label: "Yes", probability: 0.9)])),
            citations: [])],
        inputTokens: 4, outputTokens: 1, cost: 0, refusal: nil, latency: 0.5)

    var requests: [DecisionRequest] { lock.withLock { sent } }

    func decisionModels() async throws -> [DecisionModel] { try models.get() }

    func run(_ request: DecisionRequest) async throws -> DecisionResult {
        lock.withLock { sent.append(request) }
        await gate?.wait()
        return try outcome.get()
    }
}

@MainActor
struct DecisionsStoreTests {
    private func makeStore(_ service: FakeDecisionsService = FakeDecisionsService(), context: ModelContext? = nil) -> DecisionsStore {
        let store = DecisionsStore(service: service, context: context)
        store.state = "Please refund my order"
        store.addQuestion()
        store.questions[0].prompt = "Is it urgent?"
        return store
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer.anyRouter(inMemory: true)
        return (container, ModelContext(container))
    }

    @Test func modelsLoadAndTheFreeDecisionModelIsSelected() async {
        let service = FakeDecisionsService()
        service.models = .success([DecisionModel(id: "x/a", name: "A"), DecisionModel(id: "anyrouter/decision", name: "D")])
        let store = DecisionsStore(service: service)
        store.modelID = "gone"
        await store.loadModels()
        #expect(store.models.count == 2)
        #expect(store.modelID == "anyrouter/decision")
        #expect(store.modelsError == nil)
    }

    @Test func aFailedModelListIsReportedAndKeepsTheSelection() async {
        let service = FakeDecisionsService()
        service.models = .failure(TestFailure(message: "offline"))
        let store = DecisionsStore(service: service)
        await store.loadModels()
        #expect(store.modelsError == "offline")
        #expect(store.modelID == "anyrouter/decision")
    }

    @Test func questionsCanBeAddedDeletedAndReordered() {
        let store = DecisionsStore(service: FakeDecisionsService())
        for name in ["a", "b", "c"] {
            store.addQuestion()
            store.questions[store.questions.count - 1].prompt = name
        }
        store.moveQuestions(from: IndexSet(integer: 0), to: 3)
        #expect(store.questions.map(\.prompt) == ["b", "c", "a"])
        store.deleteQuestions(at: IndexSet(integer: 1))
        #expect(store.questions.map(\.prompt) == ["b", "a"])
        #expect(store.questions.allSatisfy { $0.kind == .yesNo })
    }

    @Test func runNeedsAnAnswerableForm() async {
        let service = FakeDecisionsService()
        let store = DecisionsStore(service: service)
        #expect(!store.canRun)
        await store.run()
        #expect(store.phase == .idle)
        #expect(service.requests.isEmpty)
    }

    @Test func aRunSendsTheRequestShowsTheResultAndSavesIt() async throws {
        let (container, context) = try makeContext()
        let service = FakeDecisionsService()
        let store = makeStore(service, context: context)
        #expect(store.canRun)
        await store.run()
        #expect(store.phase == .finished(FakeDecisionsService.result))
        #expect(service.requests.first?.questions.first?.id == "q1")
        #expect(service.requests.first?.model == "anyrouter/decision")
        let saved = try context.fetch(FetchDescriptor<DecisionRunRecord>())
        #expect(saved.count == 1)
        #expect(saved[0].state == "Please refund my order")
        withExtendedLifetime(container) {}
    }

    @Test func aRunWithoutAStoreStillShowsItsResult() async {
        let store = makeStore()
        await store.run()
        #expect(store.phase == .finished(FakeDecisionsService.result))
    }

    @Test func aFailedRunShowsTheMessageAndSavesNothing() async throws {
        let (container, context) = try makeContext()
        let service = FakeDecisionsService()
        service.outcome = .failure(AnyRouterError.signedOut)
        let store = makeStore(service, context: context)
        await store.run()
        #expect(store.phase == .failed(AnyRouterError.signedOut.localizedDescription))
        #expect(try context.fetchCount(FetchDescriptor<DecisionRunRecord>()) == 0)
        withExtendedLifetime(container) {}
    }

    @Test func runIsDisabledWhileARunIsInFlight() async {
        let service = FakeDecisionsService()
        let gate = DecisionGate()
        service.gate = gate
        let store = makeStore(service)
        let task = Task { await store.run() }
        while store.phase != .running { await Task.yield() }
        #expect(!store.canRun)
        gate.open()
        await task.value
        #expect(store.canRun)
    }

    @Test func onlyTheLastTwentyRunsAreKept() async throws {
        let (container, context) = try makeContext()
        for index in 0..<25 {
            context.insert(try DecisionRunRecord(
                modelID: "m", state: "run \(index)", questions: [], result: FakeDecisionsService.result,
                createdAt: Date(timeIntervalSince1970: Double(index))))
        }
        let store = makeStore(context: context)
        await store.run()
        let kept = try context.fetch(FetchDescriptor<DecisionRunRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(kept.count == DecisionsLogic.recentLimit)
        #expect(kept.first?.state == "run 6")
        #expect(kept.last?.state == "Please refund my order")
        withExtendedLifetime(container) {}
    }

    @Test func aSavedRunComesBackIntoTheForm() throws {
        let question = QuestionDraft(kind: .choice, prompt: "Team?", list: "a, b")
        let record = try DecisionRunRecord(
            modelID: "x/a", state: "old text", questions: [question], result: FakeDecisionsService.result)
        let store = DecisionsStore(service: FakeDecisionsService())
        store.restore(record)
        #expect(store.modelID == "x/a" && store.state == "old text")
        #expect(store.questions == [question])
        #expect(store.phase == .finished(FakeDecisionsService.result))
    }

    @Test func aSavedRunThatCannotBeReadLeavesTheFormAlone() throws {
        let record = try DecisionRunRecord(modelID: "x/a", state: "old", questions: [], result: FakeDecisionsService.result)
        record.resultJSON = Data("garbage".utf8)
        let store = DecisionsStore(service: FakeDecisionsService())
        store.state = "mine"
        store.restore(record)
        #expect(store.state == "mine" && store.phase == .idle)
        record.questionsJSON = Data("garbage".utf8)
        #expect(record.questions.isEmpty)
    }

    @Test func attachingAContextLetsLaterRunsBeSaved() async throws {
        let (container, context) = try makeContext()
        let store = makeStore()
        store.attach(context)
        await store.run()
        #expect(try context.fetchCount(FetchDescriptor<DecisionRunRecord>()) == 1)
        withExtendedLifetime(container) {}
    }
}
