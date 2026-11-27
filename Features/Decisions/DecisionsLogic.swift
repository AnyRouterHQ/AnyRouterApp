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
            case .rubric: "Score"
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

    /// Why Run is off, in a few words, or nil when it can run. `questionProblem` is nil for an app's fixed questions.
    static func blocker(model: String, state: String, images: [DecisionImage] = [], questionProblem: String?) -> String? {
        if model.isEmpty { return "Choose a model." }
        if state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty { return "Add something to judge." }
        if state.count > maxStateCharacters { return "The text is over \(maxStateCharacters) characters." }
        if let problem = imageProblem(images) { return problem }
        return questionProblem
    }

    /// The first thing wrong with the custom question list, or nil.
    static func questionProblem(_ questions: [QuestionDraft]) -> String? {
        if questions.isEmpty { return "Add a question." }
        return questions.lazy.compactMap { problem(with: $0) }.first
    }

    static func canRun(model: String, state: String, questions: [QuestionDraft], images: [DecisionImage] = []) -> Bool {
        blocker(model: model, state: state, images: images, questionProblem: questionProblem(questions)) == nil
    }

    // MARK: Images

    static let maxImages = 4
    static let maxImageBytes = 4 * 1024 * 1024
    static let maxTotalImageBytes = 8 * 1024 * 1024
    /// Every photo gets the same share, so four always fit both caps and a new photo never re-encodes the others.
    static let imageBudget = maxTotalImageBytes / maxImages
    /// Longest side to try, biggest first, until the JPEG fits the budget.
    static let imageSides = [2048, 1536, 1024, 768, 512]
    static let imageMediaTypes: Set<String> = ["image/png", "image/jpeg", "image/webp"]
    /// Sent as the text when only photos were added. Inferred: the server only rejects a missing `state`.
    static let photoOnlyState = "The input is in the attached photos."

    enum ImageProblem: Error, Equatable { case unreadable, tooLarge }

    /// Re-encodes one source photo as JPEG (`encode` takes the bytes and a longest side), shrinking until it fits `budget`.
    static func fit(
        _ source: Data, budget: Int = imageBudget, sides: [Int] = imageSides, encode: (Data, Int) -> Data?
    ) -> Result<DecisionImage, ImageProblem> {
        for side in sides {
            guard let jpeg = encode(source, side) else { return .failure(.unreadable) }
            if jpeg.count <= budget { return .success(DecisionImage(mediaType: "image/jpeg", data: jpeg)) }
        }
        return .failure(.tooLarge)
    }

    /// How many of `count` new photos fit beside the `held` ones.
    static func slots(adding count: Int, held: Int) -> Int { max(0, min(count, maxImages - held)) }

    /// What is wrong with the photo set, or nil. These are the server's limits.
    static func imageProblem(_ images: [DecisionImage]) -> String? {
        if images.count > maxImages { return "Add at most \(maxImages) photos." }
        if images.contains(where: { !imageMediaTypes.contains($0.mediaType) }) { return "Photos must be PNG, JPEG or WebP." }
        let total = images.reduce(0) { $0 + $1.data.count }
        if images.contains(where: { $0.data.count > maxImageBytes }) || total > maxTotalImageBytes { return "The photos are too large." }
        return nil
    }

    /// The trimmed text, or a fixed line when there are only photos.
    static func wireState(_ state: String, images: [DecisionImage]) -> String {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty && !images.isEmpty ? photoOnlyState : trimmed
    }

    /// Question ids are `q1`, `q2`, ... in list order.
    static func request(model: String, state: String, questions: [QuestionDraft], images: [DecisionImage] = []) -> DecisionRequest? {
        guard canRun(model: model, state: state, questions: questions, images: images) else { return nil }
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
        return DecisionRequest(model: model, state: wireState(state, images: images), questions: wire, images: images)
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
