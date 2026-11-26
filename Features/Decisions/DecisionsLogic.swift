import Foundation

/// One row of the questions list, as the user edits it.
struct QuestionDraft: Identifiable, Equatable, Codable {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case yesNo, choice, rubric

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yesNo: "Yes/no"
            case .choice: "Choice"
            case .rubric: "Rubric"
            }
        }

        /// Placeholder for the extra field. Yes/no has none.
        var listPrompt: String? {
            switch self {
            case .yesNo: nil
            case .choice: "Options, separated by commas"
            case .rubric: "Levels, lowest first, separated by commas"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .yesNo
    var prompt = ""
    /// Comma or line separated options (choice) or levels (rubric).
    var list = ""
}

enum DecisionsLogic {
    /// The server rejects a longer `state`.
    static let maxStateCharacters = 12_000
    static let rubricLevels = 2...10
    /// Free, and the first model to pick.
    static let defaultModelID = "anyrouter/decision"
    static let recentLimit = 20

    /// Splits "a, b\nc" into trimmed, non-empty, distinct items in order.
    static func items(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Why a question cannot run yet, or nil when it can.
    static func problem(with draft: QuestionDraft) -> String? {
        if draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write the question." }
        let count = items(draft.list).count
        switch draft.kind {
        case .yesNo: return nil
        case .choice: return count >= 2 ? nil : "Add at least two options."
        case .rubric: return rubricLevels.contains(count) ? nil : "Add 2 to 10 levels."
        }
    }

    static func canRun(model: String, state: String, questions: [QuestionDraft]) -> Bool {
        !model.isEmpty
            && !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state.count <= maxStateCharacters
            && !questions.isEmpty
            && questions.allSatisfy { problem(with: $0) == nil }
    }

    /// Question ids are `q1`, `q2`, ... in list order.
    static func request(model: String, state: String, questions: [QuestionDraft]) -> DecisionRequest? {
        guard canRun(model: model, state: state, questions: questions) else { return nil }
        let wire = questions.enumerated().map { index, draft -> DecisionQuestion in
            let kind: DecisionQuestion.Kind
            switch draft.kind {
            case .yesNo: kind = .yesNo
            case .choice: kind = .choice(options: items(draft.list))
            case .rubric: kind = .rubric(levels: items(draft.list))
            }
            return DecisionQuestion(
                id: "q\(index + 1)", prompt: draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        }
        return DecisionRequest(
            model: model, state: state.trimmingCharacters(in: .whitespacesAndNewlines), questions: wire)
    }

    /// The default model when the list has it, else the first one.
    static func initialModelID(in models: [DecisionModel], current: String) -> String {
        if models.contains(where: { $0.id == current }) { return current }
        if models.contains(where: { $0.id == defaultModelID }) { return defaultModelID }
        return models.first?.id ?? current
    }

    // MARK: Text

    static func percent(_ value: Double) -> String { "\(Int((min(1, max(0, value)) * 100).rounded()))%" }

    static func costText(_ cost: Double?) -> String {
        guard let cost else { return "Not reported" }
        return cost == 0 ? "Free" : String(format: "$%.4f", cost)
    }

    static func latencyText(_ seconds: Double) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.1f s", seconds)
    }

    /// First line of the state, for the recent-runs list.
    static func title(forState state: String) -> String {
        let line = state.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled run" : trimmed
    }
}
