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

    init(modelID: String, state: String, questions: [QuestionDraft], result: DecisionResult, createdAt: Date = Date()) throws {
        id = UUID()
        self.createdAt = createdAt
        self.modelID = modelID
        self.state = state
        questionsJSON = try JSONEncoder().encode(questions)
        resultJSON = try JSONEncoder().encode(result)
    }

    var questions: [QuestionDraft] { (try? JSONDecoder().decode([QuestionDraft].self, from: questionsJSON)) ?? [] }
    var result: DecisionResult? { try? JSONDecoder().decode(DecisionResult.self, from: resultJSON) }
}
