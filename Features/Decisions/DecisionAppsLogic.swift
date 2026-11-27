import Foundation

/// A use-case mini app: fixed questions behind a "paste or snap, then Run" screen. Bundled as `catalog/decision-apps.json`.
struct DecisionApp: Identifiable, Equatable, Codable, Sendable {
    struct Question: Equatable, Codable, Sendable {
        enum Kind: String, Codable, Sendable { case yesNo, choice, score }

        var id: String
        var prompt: String
        var type: Kind
        /// Choice options, or score levels (lowest first). Absent for yes/no.
        var items: [String]?
        /// Yes/no only: the clause the result line uses for each answer.
        var yes: String?
        var no: String?

        var list: [String] { items ?? [] }

        var decisionQuestion: DecisionQuestion {
            switch type {
            case .yesNo: DecisionQuestion(id: id, prompt: prompt, kind: .yesNo)
            case .choice: DecisionQuestion(id: id, prompt: prompt, kind: .choice(options: list))
            case .score: DecisionQuestion(id: id, prompt: prompt, kind: .rubric(levels: list))
            }
        }
    }

    struct Sample: Equatable, Codable, Sendable {
        var title: String
        var text: String
    }

    var id: String
    var title: String
    /// SF Symbol name.
    var symbol: String
    var inputHint: String
    var acceptsImages: Bool
    var defaultModel: String?
    var samples: [Sample]
    var questions: [Question]
    /// A sentence with a `{questionId}` token for each answer.
    var resultLine: String
}

/// One tile of the Apps list. Adding an app to the list is one more tile in `DecisionAppsLogic.tiles`.
struct AppTile: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case decision(DecisionApp.ID)
        case custom
    }

    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var target: Target
}

enum DecisionAppsLogic {
    /// The Apps list: each decision app, then the custom decision last.
    static func tiles(for apps: [DecisionApp]) -> [AppTile] {
        apps.map { AppTile(id: $0.id, title: $0.title, subtitle: $0.inputHint, symbol: $0.symbol, target: .decision($0.id)) }
            + [AppTile(id: "custom", title: "Custom decision", subtitle: "Write your own questions", symbol: "slider.horizontal.3", target: .custom)]
    }

    private struct Document: Decodable { var apps: [DecisionApp] }
    private final class Anchor {}

    /// Reads `decision-apps.json` from the app bundle. A missing or broken file is a build error, so this throws.
    static func load(bundle: Bundle? = nil) throws -> [DecisionApp] {
        let bundle = bundle ?? Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: "decision-apps", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "decision-apps.json is missing from the app bundle."])
        }
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).apps
    }

    // MARK: Validity

    /// What stops an app from building a request the server accepts, or nil. Score levels 2 to 10, choice options at least
    /// two and distinct, question ids unique, every result token a question id.
    static func problem(with app: DecisionApp) -> String? {
        if app.questions.isEmpty { return "\(app.id) has no questions." }
        if Set(app.questions.map(\.id)).count != app.questions.count { return "\(app.id) repeats a question id." }
        for question in app.questions {
            if question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "\(question.id) has no prompt." }
            let items = question.list
            switch question.type {
            case .yesNo:
                if !items.isEmpty { return "\(question.id) is yes/no and takes no items." }
            case .choice:
                if items.count < 2 || Set(items).count != items.count { return "\(question.id) needs two or more distinct options." }
            case .score:
                if !DecisionsLogic.rubricLevels.contains(items.count) { return "\(question.id) needs 2 to 10 levels." }
            }
        }
        let ids = Set(app.questions.map(\.id))
        if tokens(in: app.resultLine).isEmpty || !tokens(in: app.resultLine).isSubset(of: ids) {
            return "\(app.id) has a result line with a missing question id."
        }
        return nil
    }

    private static func tokens(in line: String) -> Set<String> {
        var found = Set<String>()
        for part in line.components(separatedBy: "{").dropFirst() {
            if let end = part.firstIndex(of: "}") { found.insert(String(part[..<end])) }
        }
        return found
    }

    // MARK: Run

    static func blocker(_ app: DecisionApp, model: String, state: String, images: [DecisionImage]) -> String? {
        DecisionsLogic.blocker(model: model, state: state, images: images, questionProblem: problem(with: app))
    }

    static func request(_ app: DecisionApp, model: String, state: String, images: [DecisionImage]) -> DecisionRequest? {
        guard blocker(app, model: model, state: state, images: images) == nil else { return nil }
        return DecisionRequest(
            model: model, state: DecisionsLogic.wireState(state, images: images),
            questions: app.questions.map(\.decisionQuestion), images: images)
    }

    /// The photo input shows for an app that takes photos (every custom decision does) and a model that is not known to be text only.
    static func showsImageInput(app: DecisionApp?, model: DecisionModel?) -> Bool {
        (app?.acceptsImages ?? true) && model?.acceptsImages != false
    }

    /// An app's own model when the list has it, else the usual pick.
    static func startingModelID(app: DecisionApp?, models: [DecisionModel], current: String) -> String {
        if let preferred = app?.defaultModel, models.contains(where: { $0.id == preferred }) { return preferred }
        return DecisionsLogic.initialModelID(in: models, current: current)
    }

    // MARK: Result text

    /// One answer as a few plain words. `yes` and `no` replace "Yes" and "No" when an app gives clauses.
    static func text(of outcome: DecisionAnswer.Outcome, yes: String? = nil, no: String? = nil) -> String {
        switch outcome {
        case .answered(let verdict):
            if verdict.score != nil { return verdict.note ?? "\(verdict.headline) of \(Int(verdict.maxScore ?? 0))" }
            if verdict.headline == "Yes", let yes { return yes }
            if verdict.headline == "No", let no { return no }
            return verdict.headline
        case .refused: return "declined"
        case .unreadable: return "unclear"
        }
    }

    /// The top answers as one sentence, from the app's template.
    static func resultLine(_ app: DecisionApp, result: DecisionResult) -> String {
        if let refusal = result.refusal { return "The model declined: \(refusal)" }
        var line = app.resultLine
        for question in app.questions {
            let phrase = result.answers.first { $0.id == question.id }
                .map { text(of: $0.outcome, yes: question.yes, no: question.no) } ?? "unclear"
            line = line.replacingOccurrences(of: "{\(question.id)}", with: phrase)
        }
        return line
    }

    /// The same for a custom decision: each question with its answer.
    static func summary(of result: DecisionResult) -> String {
        if let refusal = result.refusal { return "The model declined: \(refusal)" }
        return result.answers.map { "\($0.prompt) \(text(of: $0.outcome))." }.joined(separator: " ")
    }
}
