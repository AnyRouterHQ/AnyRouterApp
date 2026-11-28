import Foundation
import Observation
import SwiftData

/// State of the Decisions apps: the open app (or the custom decision), what is typed and attached, the running request,
/// the last result, and the saved runs.
@MainActor @Observable
final class DecisionsStore {
    enum Phase: Equatable {
        case idle
        case running
        case finished(DecisionResult)
        /// `canChangeModel` is true when another model would help (the photos were refused).
        case failed(message: String, canChangeModel: Bool)
    }

    private(set) var apps: [DecisionApp] = []
    private(set) var appsError: String?
    /// The open app, or `nil` for the custom decision.
    private(set) var app: DecisionApp?
    var state = ""
    /// The custom decision's questions. An app's questions are fixed and live in `app`.
    var questions: [QuestionDraft] = []
    private(set) var images: [DecisionImage] = []
    private(set) var imageError: String?
    private(set) var phase: Phase = .idle
    /// The person's pick for the open app: the saved one, or for this session the model of a restored run.
    private var pickedID: String?

    private let service: any DecisionsService
    /// Lists the decision models the picker and `selectedModel` choose from.
    let models: ModelStore
    private let picks: MiniAppModelPicks
    private var context: ModelContext?

    init(service: any DecisionsService, models: ModelStore, picks: MiniAppModelPicks = MiniAppModelPicks(), context: ModelContext? = nil) {
        self.service = service
        self.models = models
        self.picks = picks
        self.context = context
        pickedID = picks.pick(for: pickKey)
    }

    /// The screen hands over its context; runs are saved there.
    func attach(_ context: ModelContext) { self.context = context }

    // MARK: Apps

    func loadApps(bundle: Bundle? = nil) {
        do {
            apps = try DecisionAppsLogic.load(bundle: bundle)
            appsError = nil
        } catch {
            appsError = error.localizedDescription
        }
    }

    /// Opens an app (or the custom decision for `nil`) with an empty form.
    func start(_ app: DecisionApp?) {
        self.app = app
        state = ""
        questions = []
        images = []
        imageError = nil
        phase = .idle
        pickedID = picks.pick(for: pickKey)
    }

    /// The custom decision with `text` as its state, from the composer.
    func startCustom(state text: String) {
        start(nil)
        state = text
    }

    func fill(with sample: DecisionApp.Sample) { state = sample.text }

    func fill(with sample: DecisionSample) {
        state = sample.state
        questions = sample.questions
    }

    // MARK: Form

    /// Decision models only, and once a photo is attached only ones that read photos.
    var requirement: ModelRequirement { .decision(needsVision: !images.isEmpty) }

    /// The model Run uses: the person's pick, else the app's preferred model, else its fallback, else the free decision
    /// model, else any that fits. Nil signed out or when none can read the attached photos.
    var selectedModel: ModelDescriptor? {
        MiniAppModelChoice.choose(
            [pickedID, app?.preferredModel, app?.fallbackModel, DecisionsLogic.defaultModelID],
            from: models.listed(for: requirement))
    }

    /// The pick from the picker, remembered for this app.
    func choose(_ model: ModelDescriptor) {
        pickedID = model.wireID
        picks.remember(model, for: pickKey)
    }

    /// One saved pick per app, and one for the custom decision.
    private var pickKey: String {
        guard let app else { return "decisions.custom" }
        return "decisions.\(app.id)"
    }

    /// The wire id the request sends, empty when no model fits (Run then says "Choose a model.").
    private var modelID: String {
        guard let selectedModel else { return "" }
        return selectedModel.wireID
    }

    var showsImageInput: Bool { DecisionAppsLogic.showsImageInput(app: app, model: selectedModel) }

    /// Why Run is off, or nil.
    var blocker: String? {
        if let app { return DecisionAppsLogic.blocker(app, model: modelID, state: state, images: images) }
        return DecisionsLogic.blocker(
            model: modelID, state: state, images: images, questionProblem: DecisionsLogic.questionProblem(questions))
    }

    var canRun: Bool { phase != .running && blocker == nil }

    func loadModels() async {
        guard models.decisionModels.isEmpty else { return }
        await models.refreshDecisionModels()
    }

    // MARK: Questions

    func addQuestion(_ kind: QuestionDraft.Kind = .yesNo) {
        questions.append(QuestionDraft(kind: kind, list: kind == .rubric ? DecisionsLogic.defaultLevels : ""))
    }

    func deleteQuestions(at offsets: IndexSet) { questions.remove(atOffsets: offsets) }

    // MARK: Photos

    /// Shrinks each picked photo to a JPEG that fits, up to four in all. Says why when one cannot be added.
    func addImages(_ sources: [Data]) async {
        let room = DecisionsLogic.slots(adding: sources.count, held: images.count)
        imageError = room < sources.count ? DecisionsLogic.imageProblemText(.tooMany) : nil
        for source in sources.prefix(room) {
            switch await Self.fit(source) {
            case .success(let image): images.append(image)
            case .failure(let problem): imageError = DecisionsLogic.imageProblemText(problem)
            }
        }
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        imageError = nil
    }

    @concurrent private static func fit(_ source: Data) async -> Result<DecisionImage, DecisionsLogic.ImageProblem> {
        DecisionsLogic.fit(source) { ImageProcessing.jpeg(from: $0, maxSide: $1) }
    }

    // MARK: Run

    private var request: DecisionRequest? {
        if let app { return DecisionAppsLogic.request(app, model: modelID, state: state, images: images) }
        return DecisionsLogic.request(model: modelID, state: state, questions: questions, images: images)
    }

    func run() async {
        guard canRun, let request else { return }
        phase = .running
        do {
            let result = try await service.run(request)
            phase = .finished(result)
            save(result)
        } catch {
            phase = .failed(message: error.localizedDescription, canChangeModel: error is DecisionRunError)
        }
    }

    /// Puts a saved run back into the form, with its result. Photos are not kept.
    func restore(_ record: DecisionRunRecord) {
        guard let result = record.result else { return }
        app = apps.first { $0.id == record.appID }
        pickedID = record.modelID
        state = record.state
        questions = record.questions
        images = []
        imageError = nil
        phase = .finished(result)
    }

    private func save(_ result: DecisionResult) {
        guard let context, let record = try? DecisionRunRecord(
            modelID: modelID, state: state, questions: questions, result: result, appID: app?.id ?? "") else { return }
        context.insert(record)
        if let all = try? context.fetch(FetchDescriptor<DecisionRunRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])) {
            for old in all.dropFirst(DecisionsLogic.recentLimit) { context.delete(old) }
        }
        try? context.save()
    }
}
