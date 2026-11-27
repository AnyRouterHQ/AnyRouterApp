import Foundation
import SwiftData

/// One finished run, kept so it can be reopened. Only the last `DecisionsLogic.recentLimit` stay.
@Model
final class DecisionRunRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var modelID: String
    var state: String
    var questionsJSON: Data
    var resultJSON: Data
    /// The app that made the run. Empty for a custom decision (and for runs saved before apps).
    var appID: String = ""

    init(modelID: String, state: String, questions: [QuestionDraft], result: DecisionResult, appID: String = "", createdAt: Date = Date()) throws {
        id = UUID()
        self.createdAt = createdAt
        self.modelID = modelID
        self.state = state
        self.appID = appID
        questionsJSON = try JSONEncoder().encode(questions)
        resultJSON = try JSONEncoder().encode(result)
    }

    var questions: [QuestionDraft] { (try? JSONDecoder().decode([QuestionDraft].self, from: questionsJSON)) ?? [] }
    var result: DecisionResult? { try? JSONDecoder().decode(DecisionResult.self, from: resultJSON) }
}
