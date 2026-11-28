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
    var models: Result<[ModelDescriptor], Error> = .success([testDecision("anyrouter/decision"), testDecision("google/gemini-decision-1", vision: true)])
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

    func decisionModels() async throws -> [ModelDescriptor] { try models.get() }

    func run(_ request: DecisionRequest) async throws -> DecisionResult {
        lock.withLock { sent.append(request) }
        await gate?.wait()
        return try outcome.get()
    }
}

/// A decision model as the catalog lists it: `wire` is the id the request sends.
func testDecision(_ wire: String, vision: Bool = false, installed: Bool = true) -> ModelDescriptor {
    var model = testModel(id: "anyrouter/\(wire)", source: .anyrouter, installed: installed)
    model.capabilities = vision ? ["decision", "vision"] : ["decision"]
    return model
}

@MainActor
struct DecisionsStoreTests {
    /// A store whose model list comes from `service`, with its own defaults so saved picks never leak between tests.
    private func newStore(
        _ service: FakeDecisionsService = FakeDecisionsService(), context: ModelContext? = nil, defaults: UserDefaults = testDefaults()
    ) -> DecisionsStore {
        let models = ModelStore(registry: EngineRegistry(), defaults: defaults)
        models.decisionSource = service
        return DecisionsStore(service: service, models: models, picks: MiniAppModelPicks(defaults: defaults), context: context)
    }

    private func makeStore(_ service: FakeDecisionsService = FakeDecisionsService(), context: ModelContext? = nil) async -> DecisionsStore {
        let store = newStore(service, context: context)
        await store.loadModels()
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
        service.models = .success([testDecision("x/a"), testDecision("anyrouter/decision")])
        let store = newStore(service)
        #expect(store.selectedModel == nil, "nothing to run before the list loads")
        await store.loadModels()
        #expect(store.models.decisionModels.count == 2)
        #expect(store.selectedModel?.wireID == "anyrouter/decision")
        #expect(store.models.decisionLoadFailure == nil)
    }

    @Test func aFailedModelListIsReportedAndRunAsksForAModel() async {
        let service = FakeDecisionsService()
        service.models = .failure(TestFailure(message: "offline"))
        let store = newStore(service)
        await store.loadModels()
        #expect(store.models.decisionLoadFailure == "offline")
        #expect(store.selectedModel == nil && store.blocker == "Choose a model.")
    }

    /// Signed out every decision model is listed but none can run, so Run waits for a sign-in.
    @Test func signedOutNoModelIsChosen() async {
        let service = FakeDecisionsService()
        service.models = .success([testDecision("anyrouter/decision", installed: false)])
        let store = await makeStore(service)
        #expect(store.selectedModel == nil && !store.canRun)
    }

    /// The pick is saved per app: another app keeps its own model, and a new store finds the pick again.
    @Test func aPickIsRememberedForItsAppOnly() async throws {
        let defaults = testDefaults()
        let service = FakeDecisionsService()
        service.models = .success([testDecision("anyrouter/decision"), testDecision("scira/amos-1-large"), testDecision("google/gemini-decision-1", vision: true)])
        let store = newStore(service, defaults: defaults)
        store.loadApps()
        await store.loadModels()
        let email = try #require(store.apps.first { $0.id == "email-triage" })
        let receipt = try #require(store.apps.first { $0.id == "receipt-sort" })
        store.start(email)
        store.choose(try #require(store.models.decisionModels.first { $0.wireID == "scira/amos-1-large" }))
        store.start(receipt)
        #expect(store.selectedModel?.wireID == "google/gemini-decision-1")
        let again = newStore(service, defaults: defaults)
        again.loadApps()
        await again.loadModels()
        again.start(email)
        #expect(again.selectedModel?.wireID == "scira/amos-1-large")
        #expect(defaults.string(forKey: "miniApps.model.decisions.receipt-sort") == nil)
    }

    /// A photo leaves out every model that cannot read it, without forgetting the text-only pick.
    @Test func aPhotoSwitchesToAModelThatReadsIt() async throws {
        let store = await makeStore()
        store.choose(try #require(store.models.decisionModels.first { $0.wireID == "anyrouter/decision" }))
        await store.addImages([jpeg()])
        #expect(store.requirement == .decision(needsVision: true))
        #expect(store.selectedModel?.wireID == "google/gemini-decision-1")
        store.removeImage(at: 0)
        #expect(store.selectedModel?.wireID == "anyrouter/decision")
    }

    @Test func questionsCanBeAddedAndDeleted() {
        let store = newStore()
        for name in ["a", "b", "c"] {
            store.addQuestion()
            store.questions[store.questions.count - 1].prompt = name
        }
        store.deleteQuestions(at: IndexSet(integer: 1))
        #expect(store.questions.map(\.prompt) == ["a", "c"])
        #expect(store.questions.allSatisfy { $0.kind == .yesNo })
    }

    @Test func aScoreQuestionStartsWithTenLevels() {
        let store = newStore()
        store.addQuestion(.rubric)
        store.addQuestion(.choice)
        #expect(DecisionsLogic.items(store.questions[0].list).count == 10)
        #expect(store.questions[1].list.isEmpty)
        #expect(store.questions.map(\.kind) == [.rubric, .choice])
    }

    @Test func runNeedsAnAnswerableForm() async {
        let service = FakeDecisionsService()
        let store = newStore(service)
        #expect(!store.canRun)
        await store.run()
        #expect(store.phase == .idle)
        #expect(service.requests.isEmpty)
    }

    @Test func aRunSendsTheRequestShowsTheResultAndSavesIt() async throws {
        let (container, context) = try makeContext()
        let service = FakeDecisionsService()
        let store = await makeStore(service, context: context)
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
        let store = await makeStore()
        await store.run()
        #expect(store.phase == .finished(FakeDecisionsService.result))
    }

    @Test func aFailedRunShowsTheMessageAndSavesNothing() async throws {
        let (container, context) = try makeContext()
        let service = FakeDecisionsService()
        service.outcome = .failure(AnyRouterError.signedOut)
        let store = await makeStore(service, context: context)
        await store.run()
        #expect(store.phase == .failed(message: AnyRouterError.signedOut.localizedDescription, canChangeModel: false))
        #expect(try context.fetchCount(FetchDescriptor<DecisionRunRecord>()) == 0)
        withExtendedLifetime(container) {}
    }

    @Test func runIsDisabledWhileARunIsInFlight() async {
        let service = FakeDecisionsService()
        let gate = DecisionGate()
        service.gate = gate
        let store = await makeStore(service)
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
        let store = await makeStore(context: context)
        await store.run()
        let kept = try context.fetch(FetchDescriptor<DecisionRunRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(kept.count == DecisionsLogic.recentLimit)
        #expect(kept.first?.state == "run 6")
        #expect(kept.last?.state == "Please refund my order")
        withExtendedLifetime(container) {}
    }

    @Test func aSavedRunComesBackIntoTheForm() async throws {
        let question = QuestionDraft(kind: .choice, prompt: "Team?", list: "a, b")
        let record = try DecisionRunRecord(
            modelID: "x/a", state: "old text", questions: [question], result: FakeDecisionsService.result)
        let service = FakeDecisionsService()
        service.models = .success([testDecision("anyrouter/decision"), testDecision("x/a")])
        let store = newStore(service)
        await store.loadModels()
        store.restore(record)
        #expect(store.selectedModel?.wireID == "x/a" && store.state == "old text")
        #expect(store.questions == [question])
        #expect(store.phase == .finished(FakeDecisionsService.result))
    }

    @Test func aSavedRunThatCannotBeReadLeavesTheFormAlone() throws {
        let record = try DecisionRunRecord(modelID: "x/a", state: "old", questions: [], result: FakeDecisionsService.result)
        record.resultJSON = Data("garbage".utf8)
        let store = newStore()
        store.state = "mine"
        store.restore(record)
        #expect(store.state == "mine" && store.phase == .idle)
        record.questionsJSON = Data("garbage".utf8)
        #expect(record.questions.isEmpty)
    }

    @Test func attachingAContextLetsLaterRunsBeSaved() async throws {
        let (container, context) = try makeContext()
        let store = await makeStore()
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

    private func appStore(_ service: FakeDecisionsService = FakeDecisionsService(), context: ModelContext? = nil) async throws -> (DecisionsStore, DecisionApp) {
        let store = newStore(service, context: context)
        store.loadApps()
        await store.loadModels()
        let app = try #require(store.apps.first { $0.id == "receipt-sort" })
        return (store, app)
    }

    @Test func theBundledAppsLoadAndAMissingFileIsReported() async throws {
        let (store, _) = try await appStore()
        #expect(store.apps.count == 7 && store.appsError == nil)
        let broken = newStore()
        broken.loadApps(bundle: Bundle(path: NSTemporaryDirectory()))
        #expect(broken.apps.isEmpty && broken.appsError != nil)
    }

    @Test func openingAnAppClearsTheFormAndPicksItsModel() async throws {
        let service = FakeDecisionsService()
        service.models = .success([testDecision("anyrouter/decision"), testDecision("google/gemini-decision-1", vision: true)])
        let (store, app) = try await appStore(service)
        store.state = "old"
        store.addQuestion()
        await store.loadModels()
        store.start(app)
        #expect(store.state.isEmpty && store.questions.isEmpty && store.images.isEmpty && store.phase == .idle)
        #expect(store.app == app && store.selectedModel?.wireID == "google/gemini-decision-1")
        store.start(nil)
        #expect(store.app == nil && store.selectedModel?.wireID == "anyrouter/decision", "the custom decision starts on the free model")
    }

    @Test func anAppOpenedBeforeTheModelsArriveStillGetsItsModel() async throws {
        let service = FakeDecisionsService()
        let store = newStore(service)
        store.loadApps()
        store.start(try #require(store.apps.first { $0.id == "receipt-sort" }))
        await store.loadModels()
        #expect(store.selectedModel?.wireID == "google/gemini-decision-1")
        service.models = .failure(TestFailure(message: "offline"))
        await store.loadModels()
        #expect(store.models.decisionLoadFailure == nil, "a loaded list is not fetched again")
    }

    @Test func theComposerOpensTheCustomDecisionWithItsText() {
        let store = newStore()
        store.startCustom(state: "Should I reply?")
        #expect(store.app == nil && store.state == "Should I reply?" && store.questions.isEmpty)
    }

    @Test func samplesFillTheTextAndForTheCustomDecisionTheQuestions() async throws {
        let (store, app) = try await appStore()
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
        let (store, app) = try await appStore(service)
        store.start(app)
        #expect(store.blocker == "Add something to judge." && !store.canRun)
        store.state = "Corner Cafe total 9.40"
        #expect(store.blocker == nil && store.canRun)
        await store.run()
        #expect(service.requests.first?.questions.map(\.id) == ["business", "category", "deductible"])
    }

    @Test func theCustomDecisionNeedsAQuestionBeforeRun() async {
        let store = newStore()
        await store.loadModels()
        store.state = "text"
        #expect(store.blocker == "Add a question.")
        store.addQuestion()
        #expect(store.blocker == "Write the question.")
    }

    @Test func photoInputFollowsTheAppAndTheModel() async throws {
        let service = FakeDecisionsService()
        service.models = .success([testDecision("x/t"), testDecision("x/v", vision: true)])
        let (store, app) = try await appStore(service)
        store.start(app)
        #expect(store.selectedModel?.wireID == "x/t", "neither named model is listed, so the first one that runs")
        #expect(!store.showsImageInput)
        store.choose(try #require(store.models.decisionModels.last))
        #expect(store.showsImageInput && store.selectedModel?.wireID == "x/v")
    }

    @Test func photosAreAddedShrunkCappedAndRemoved() async throws {
        let service = FakeDecisionsService()
        let store = await makeStore(service)
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
        let store = await makeStore(service)
        await store.run()
        #expect(store.phase == .failed(message: "This model can't read photos. Choose another model.", canChangeModel: true))
    }

    @Test func aSavedAppRunReopensItsApp() async throws {
        let (container, context) = try makeContext()
        let (store, app) = try await appStore(context: context)
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
