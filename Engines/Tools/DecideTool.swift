import Foundation

/// `decide`: one yes or no, or multiple-choice, question about a text, answered by an AnyRouter decision model with
/// its probabilities (PLAN D29). The Decisions screen uses the same `DecisionsService`. It spends AnyRouter credits; the
/// cost shows on its row and in the reply. In a cloud chat it reads: AnyRouter already has the chat. In an Apple or
/// local chat it is an external call that sends chat text to the cloud, so it asks every time, with the notice of
/// "Ask a cloud model". It has its own switch under Tools > AnyRouter.
struct DecideTool: BuiltInTool {
    static let toolName = "decide"

    let service: any DecisionsService
    let name = DecideTool.toolName
    let title = "Decide"
    let summary = "Ask a decision model about a text"
    let description = "Ask a decision model one question about a text and get a calibrated answer: yes or no, or one of the options you give, with probabilities. Use it to classify or judge a text, not to look things up."
    let inputSchemaJSON = #"{"type":"object","properties":{"text":{"type":"string","description":"The text to judge."},"question":{"type":"string","description":"One question about the text."},"options":{"type":"array","items":{"type":"string"},"description":"Answers to choose from. Leave out for a yes or no question."}},"required":["text","question"]}"#
    let needsNetwork = true
    let sideEffect: ToolSideEffect
    let sourceID = ToolSourceCatalog.anyRouter.id

    /// `onDevice`: the chat's model runs on this device, so the text would leave it.
    init(service: any DecisionsService, onDevice: Bool = false) {
        self.service = service
        sideEffect = onDevice ? .external : .read
    }

    var approvalNote: String? {
        sideEffect == .external
            ? "This chat's text goes to AnyRouter so a decision model can answer, and it uses your AnyRouter credits." : nil
    }

    func run(_ arguments: JSONValue) async throws -> String { try await runCosted(arguments).text }

    func runCosted(_ arguments: JSONValue) async throws -> (text: String, costUSD: Decimal?) {
        let result = try await service.run(Self.request(from: arguments))
        return (Self.render(result), result.cost.map { Decimal($0) })
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
