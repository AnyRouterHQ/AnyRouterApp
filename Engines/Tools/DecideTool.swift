import Foundation

/// `decide`: one yes or no, or multiple-choice, question about a text, answered by an AnyRouter decision model with
/// its probabilities (PLAN D29). The Decisions screen uses the same `DecisionsService`. Offered to cloud models only.
/// It reads: the text goes to AnyRouter, which already has the chat, and nothing changes. A reply shows it as AnyRouter's.
struct DecideTool: BuiltInTool {
    static let toolName = "decide"

    let service: any DecisionsService
    let name = DecideTool.toolName
    let title = "Decide"
    let summary = "Ask a decision model about a text"
    let description = "Ask a decision model one question about a text and get a calibrated answer: yes or no, or one of the options you give, with probabilities. Use it to classify or judge a text, not to look things up."
    let inputSchemaJSON = #"{"type":"object","properties":{"text":{"type":"string","description":"The text to judge."},"question":{"type":"string","description":"One question about the text."},"options":{"type":"array","items":{"type":"string"},"description":"Answers to choose from. Leave out for a yes or no question."}},"required":["text","question"]}"#
    let needsNetwork = true
    let sideEffect = ToolSideEffect.read
    let sourceID = ToolSourceCatalog.anyRouter.id

    func run(_ arguments: JSONValue) async throws -> String {
        Self.render(try await service.run(Self.request(from: arguments)))
    }

    static func request(from arguments: JSONValue) throws -> DecisionRequest {
        guard let text = arguments["text"]?.string, !text.isEmpty else { throw BuiltInToolError("Missing the \"text\" argument.") }
        guard let question = arguments["question"]?.string, !question.isEmpty else {
            throw BuiltInToolError("Missing the \"question\" argument.")
        }
        let options = arguments["options"]?.array?.compactMap(\.string) ?? []
        guard options.count != 1 else { throw BuiltInToolError("Give two or more options, or none for a yes or no question.") }
        let kind: DecisionQuestion.Kind = options.isEmpty ? .yesNo : .choice(options: options)
        return DecisionRequest(
            model: DecisionsLogic.defaultModelID, state: text, questions: [DecisionQuestion(id: "answer", prompt: question, kind: kind)])
    }

    /// "Yes (87%). All answers: Yes 87%, No 13%", or why there is no answer.
    static func render(_ result: DecisionResult) -> String {
        if let refusal = result.refusal { return "The decision model declined: \(refusal)" }
        guard let answer = result.answers.first else { return "The decision model did not answer." }
        switch answer.outcome {
        case .answered(let verdict):
            var line = verdict.headline
            if let probability = verdict.probability { line += " (\(percent(probability)))" }
            if !verdict.options.isEmpty {
                line += ". All answers: " + verdict.options.map { "\($0.label) \(percent($0.probability))" }.joined(separator: ", ")
            }
            return line
        case .refused(let reason): return "The decision model declined: \(reason)"
        case .unreadable: return "The decision model's answer could not be read."
        }
    }

    private static func percent(_ probability: Double) -> String { "\(Int((probability * 100).rounded()))%" }
}
