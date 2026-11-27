import Foundation
import SwiftData
import Testing
import UIKit
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

    @Test func questionsCanBeAddedAndDeleted() {
        let store = DecisionsStore(service: FakeDecisionsService())
        for name in ["a", "b", "c"] {
            store.addQuestion()
            store.questions[store.questions.count - 1].prompt = name
        }
        store.deleteQuestions(at: IndexSet(integer: 1))
        #expect(store.questions.map(\.prompt) == ["a", "c"])
        #expect(store.questions.allSatisfy { $0.kind == .yesNo })
    }

    @Test func aScoreQuestionStartsWithTenLevels() {
        let store = DecisionsStore(service: FakeDecisionsService())
        store.addQuestion(.rubric)
        store.addQuestion(.choice)
        #expect(DecisionsLogic.items(store.questions[0].list).count == 10)
        #expect(store.questions[1].list.isEmpty)
        #expect(store.questions.map(\.kind) == [.rubric, .choice])
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
        #expect(store.phase == .failed(message: AnyRouterError.signedOut.localizedDescription, canChangeModel: false))
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

    // MARK: Apps

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
    }

    private func appStore(_ service: FakeDecisionsService = FakeDecisionsService(), context: ModelContext? = nil) throws -> (DecisionsStore, DecisionApp) {
        let store = DecisionsStore(service: service, context: context)
        store.loadApps()
        let app = try #require(store.apps.first { $0.id == "receipt-sort" })
        return (store, app)
    }

    @Test func theBundledAppsLoadAndAMissingFileIsReported() throws {
        let (store, _) = try appStore()
        #expect(store.apps.count == 6 && store.appsError == nil)
        let broken = DecisionsStore(service: FakeDecisionsService())
        broken.loadApps(bundle: Bundle(path: NSTemporaryDirectory()))
        #expect(broken.apps.isEmpty && broken.appsError != nil)
    }

    @Test func openingAnAppClearsTheFormAndPicksItsModel() async throws {
        let service = FakeDecisionsService()
        service.models = .success([DecisionModel(id: "anyrouter/decision", name: "D"), DecisionModel(id: "google/gemini-decision-1", name: "G", acceptsImages: true)])
        let (store, app) = try appStore(service)
        store.state = "old"
        store.addQuestion()
        await store.loadModels()
        store.start(app)
        #expect(store.state.isEmpty && store.questions.isEmpty && store.images.isEmpty && store.phase == .idle)
        #expect(store.app == app && store.modelID == "google/gemini-decision-1")
        store.start(nil)
        #expect(store.app == nil && store.modelID == "google/gemini-decision-1")
    }

    @Test func anAppOpenedBeforeTheModelsArriveStillGetsItsModel() async throws {
        let service = FakeDecisionsService()
        service.models = .success([DecisionModel(id: "anyrouter/decision", name: "D"), DecisionModel(id: "google/gemini-decision-1", name: "G")])
        let (store, app) = try appStore(service)
        store.start(app)
        await store.loadModels()
        #expect(store.modelID == "google/gemini-decision-1")
        service.models = .failure(TestFailure(message: "offline"))
        await store.loadModels()
        #expect(store.modelsError == nil, "a loaded list is not fetched again")
    }

    @Test func theComposerOpensTheCustomDecisionWithItsText() {
        let store = DecisionsStore(service: FakeDecisionsService())
        store.startCustom(state: "Should I reply?")
        #expect(store.app == nil && store.state == "Should I reply?" && store.questions.isEmpty)
    }

    @Test func samplesFillTheTextAndForTheCustomDecisionTheQuestions() throws {
        let (store, app) = try appStore()
        store.start(app)
        store.fill(with: app.samples[0])
        #expect(store.state == app.samples[0].text)
        let sample = DecisionsLogic.samples[0]
        store.start(nil)
        store.fill(with: sample)
        #expect(store.state == sample.state && store.questions == sample.questions && store.canRun)
    }

    @Test func runFollowsTheAppsFixedQuestionsAndNeedsOnlyContent() async throws {
        let service = FakeDecisionsService()
        let (store, app) = try appStore(service)
        store.start(app)
        #expect(store.blocker == "Add something to judge." && !store.canRun)
        store.state = "Corner Cafe total 9.40"
        #expect(store.blocker == nil && store.canRun)
        await store.run()
        #expect(service.requests.first?.questions.map(\.id) == ["business", "category", "deductible"])
    }

    @Test func theCustomDecisionNeedsAQuestionBeforeRun() {
        let store = DecisionsStore(service: FakeDecisionsService())
        store.state = "text"
        #expect(store.blocker == "Add a question.")
        store.addQuestion()
        #expect(store.blocker == "Write the question.")
    }

    @Test func photoInputFollowsTheAppAndTheModel() throws {
        let (store, app) = try appStore()
        store.models = [DecisionModel(id: "t", name: "T", acceptsImages: false), DecisionModel(id: "v", name: "V", acceptsImages: true)]
        store.start(app)
        store.modelID = "t"
        #expect(!store.showsImageInput)
        store.modelID = "v"
        #expect(store.showsImageInput && store.selectedModel?.name == "V")
    }

    @Test func photosAreAddedShrunkCappedAndRemoved() async throws {
        let service = FakeDecisionsService()
        let store = makeStore(service)
        await store.addImages([jpeg(), Data("nope".utf8)])
        #expect(store.images.count == 1 && store.images[0].mediaType == "image/jpeg")
        #expect(store.imageError == "That photo could not be read.")
        await store.addImages([jpeg(), jpeg(), jpeg(), jpeg()])
        #expect(store.images.count == 4 && store.imageError == "You can add up to 4 photos.")
        await store.run()
        #expect(service.requests.first?.images.count == 4)
        store.removeImage(at: 9)
        #expect(store.images.count == 4)
        store.removeImage(at: 0)
        #expect(store.images.count == 3 && store.imageError == nil)
    }

    @Test func aRefusedPhotoOffersAnotherModel() async {
        let service = FakeDecisionsService()
        service.outcome = .failure(DecisionRunError.imagesRefused(serverMessage: "bad"))
        let store = makeStore(service)
        await store.run()
        #expect(store.phase == .failed(message: "This model can't read photos. Choose another model.", canChangeModel: true))
    }

    @Test func aSavedAppRunReopensItsApp() async throws {
        let (container, context) = try makeContext()
        let (store, app) = try appStore(context: context)
        store.start(app)
        store.state = "Receipt text"
        await store.run()
        let record = try #require(try context.fetch(FetchDescriptor<DecisionRunRecord>()).first)
        #expect(record.appID == "receipt-sort")
        store.start(nil)
        store.restore(record)
        #expect(store.app == app && store.state == "Receipt text")
        record.appID = "gone"
        store.restore(record)
        #expect(store.app == nil)
        withExtendedLifetime(container) {}
    }
}
