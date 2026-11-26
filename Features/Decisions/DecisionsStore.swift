import Foundation
import Observation
import SwiftData

/// State of the Decisions screen: the form, the running request, the last result, and the saved runs.
@MainActor @Observable
final class DecisionsStore {
    enum Phase: Equatable {
        case idle
        case running
        case finished(DecisionResult)
        case failed(String)
    }

    var models: [DecisionModel] = []
    var modelID = DecisionsLogic.defaultModelID
    var state = ""
    var questions: [QuestionDraft] = []
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

    var canRun: Bool {
        phase != .running && DecisionsLogic.canRun(model: modelID, state: state, questions: questions)
    }

    func loadModels() async {
        do {
            models = try await service.decisionModels()
            modelsError = nil
            modelID = DecisionsLogic.initialModelID(in: models, current: modelID)
        } catch {
            modelsError = error.localizedDescription
        }
    }

    // MARK: Questions

    func addQuestion() { questions.append(QuestionDraft()) }

    func deleteQuestions(at offsets: IndexSet) { questions.remove(atOffsets: offsets) }

    func moveQuestions(from source: IndexSet, to destination: Int) {
        questions.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Run

    func run() async {
        guard canRun, let request = DecisionsLogic.request(model: modelID, state: state, questions: questions) else {
            return
        }
        phase = .running
        do {
            let result = try await service.run(request)
            phase = .finished(result)
            save(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Puts a saved run back into the form, with its result.
    func restore(_ record: DecisionRunRecord) {
        guard let result = record.result else { return }
        modelID = record.modelID
        state = record.state
        questions = record.questions
        phase = .finished(result)
    }

    private func save(_ result: DecisionResult) {
        guard let context, let record = try? DecisionRunRecord(
            modelID: modelID, state: state, questions: questions, result: result) else { return }
        context.insert(record)
        let all = (try? context.fetch(FetchDescriptor<DecisionRunRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        for old in all.dropFirst(DecisionsLogic.recentLimit) { context.delete(old) }
        try? context.save()
    }
}
