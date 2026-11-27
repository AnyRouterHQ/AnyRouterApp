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
    var models: [DecisionModel] = []
    var modelID = DecisionsLogic.defaultModelID
    var state = ""
    /// The custom decision's questions. An app's questions are fixed and live in `app`.
    var questions: [QuestionDraft] = []
    private(set) var images: [DecisionImage] = []
    private(set) var imageError: String?
    private(set) var phase: Phase = .idle
    private(set) var modelsError: String?

    private let service: any DecisionsService
    private var context: ModelContext?

    init(service: any DecisionsService, context: ModelContext? = nil) {
        self.service = service
        self.context = context
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
        modelID = DecisionAppsLogic.startingModelID(app: app, models: models, current: modelID)
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

    var selectedModel: DecisionModel? { models.first { $0.id == modelID } }

    var showsImageInput: Bool { DecisionAppsLogic.showsImageInput(app: app, model: selectedModel) }

    /// Why Run is off, or nil.
    var blocker: String? {
        if let app { return DecisionAppsLogic.blocker(app, model: modelID, state: state, images: images) }
        return DecisionsLogic.blocker(
            model: modelID, state: state, images: images, questionProblem: DecisionsLogic.questionProblem(questions))
    }

    var canRun: Bool { phase != .running && blocker == nil }

    func loadModels() async {
        guard models.isEmpty else { return }
        do {
            models = try await service.decisionModels()
            modelsError = nil
            modelID = DecisionAppsLogic.startingModelID(app: app, models: models, current: modelID)
        } catch {
            modelsError = error.localizedDescription
        }
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
        modelID = record.modelID
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
