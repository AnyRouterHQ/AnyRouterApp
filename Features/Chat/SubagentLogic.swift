import Foundation

/// A piece of work the model handed to another run of a model, with the steps that run took and what it answered.
struct Subagent: Equatable, Identifiable {
    let id: String
    let title: String
    /// "Haiku 4.5": the short name of the model it ran on, when the call named one.
    let modelLabel: String?
    let steps: [ToolStep]
    /// What it answered, once it is done.
    let result: String?
    let status: TraceStatus
}

/// Reads a subagent out of the delegate tool call that started it. Pure, so the card is tested without a model.
enum SubagentLogic {
    /// The tool a model calls to hand work to a subagent. Its `children` are the subagent's own steps.
    static let toolName = "delegate_task"

    static func isSubagent(_ step: ToolStep) -> Bool { step.call.name == toolName }

    /// Nil for any call that is not a delegation.
    static func make(_ step: ToolStep) -> Subagent? {
        guard isSubagent(step) else { return nil }
        var title = ""
        var model: String?
        if let object = (try? JSONSerialization.jsonObject(with: Data(step.call.argumentsJSON.utf8))) as? [String: Any] {
            if let text = object["title"] as? String { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let id = object["model"] as? String, !id.isEmpty { model = ModelShortLabel.make(ResponseFormat.prettyName(id)) }
        }
        var steps: [ToolStep] = []
        if let children = step.children { steps = children }
        let status = ToolRowLogic.status(of: step)
        return Subagent(
            id: step.id, title: title.isEmpty ? String(localized: "Task") : title, modelLabel: model, steps: steps,
            result: status == .done ? step.result?.text : nil, status: status)
    }

    /// "Subagent · Research · 4 steps". A subagent that has not made a call yet has no count.
    static func heading(_ subagent: Subagent) -> String {
        switch subagent.steps.count {
        case 0: String(localized: "Subagent · \(subagent.title)")
        case 1: String(localized: "Subagent · \(subagent.title) · 1 step")
        default: String(localized: "Subagent · \(subagent.title) · \(subagent.steps.count) steps")
        }
    }

    // MARK: Running one (PLAN D28 S1, cloud models only)

    /// Model requests a subagent may make: three that may call tools, then one that must answer.
    static let maxRounds = 4
    /// Prompt and completion tokens of all its requests; the round that reaches it is the last with tools.
    static let tokenBudget = 30_000
    /// The only tools a subagent gets: web search, the page reader, the clock and the calculator. Never memory, notes,
    /// `decide`, a write, an external tool or another subagent.
    static let childToolNames: Set<String> = [WebSearchBinding.name, FetchURLTool.toolName, CurrentDateTimeTool().name, CalculatorTool().name]
    static let missingTaskText = "Missing the \"task\" argument."
    static let noSummaryText = "The subagent stopped without a summary."

    static let spec = ToolSpec(
        name: toolName, title: "Research",
        description: """
            Hands one research question to a helper that searches the web and reads pages on its own, then answers with \
            a short summary and its sources. Use it for a question that needs several searches or pages. The helper does \
            not see this chat, so put everything it needs in the task.
            """,
        inputSchemaJSON: ##"{"type":"object","properties":{"task":{"type":"string","description":"The question, with everything the helper needs to know."},"title":{"type":"string","description":"Two to four words the user sees, such as Compare prices."},"hints":{"type":"string","description":"Where to look or what to leave out."}},"required":["task"]}"##,
        sideEffect: .read)

    /// The subagent's system prompt. It never sees the chat, the user's instructions or memory.
    static let instructions = """
        You research one task for another assistant, who reads only your last message. Use the tools to find the facts, \
        then answer in one short summary of at most 300 words. End with a line "Sources:" and the address of each page \
        you used. You cannot ask questions; work with what you find.
        """

    /// A subagent is offered only when it can read the web: offline, or with web search and the page reader off, the clock
    /// and the calculator alone are no research.
    static func canResearch(_ specs: [ToolSpec]) -> Bool {
        specs.contains { $0.name == WebSearchBinding.name || $0.name == FetchURLTool.toolName }
    }

    /// The subagent's only message: the task, then the hints. Nil when the call has no task.
    static func message(from argumentsJSON: String) -> String? {
        let arguments = MCPToolHost.arguments(from: argumentsJSON)
        guard let task = arguments?["task"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty else { return nil }
        guard let hints = arguments?["hints"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !hints.isEmpty else { return task }
        return task + "\n\nHints: " + hints
    }

    /// What the parent reads: the summary, then each page the subagent read that the summary does not name. Nil when it
    /// wrote no summary.
    static func answer(_ summary: String, steps: [ToolStep]) -> String? {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let unnamed = pagesRead(steps).filter { !text.contains($0) }
        guard !unnamed.isEmpty else { return text }
        return text + "\n\nPages read:\n" + unnamed.map { "- " + $0 }.joined(separator: "\n")
    }

    /// The addresses of the pages the subagent read without an error, in order and without repeats.
    static func pagesRead(_ steps: [ToolStep]) -> [String] {
        var seen = Set<String>()
        return steps.filter { $0.call.name == FetchURLTool.toolName && $0.result?.isError == false }
            .flatMap { ExfiltrationGuard.urls(in: .string($0.call.argumentsJSON)) }
            .filter { seen.insert($0).inserted }
    }

    /// `steps` with `children` on `call`'s step, which is added when its row has not arrived yet: the subagent's first
    /// step can land before the chat reads the call.
    static func nesting(_ children: [ToolStep], under call: ToolCall, in steps: [ToolStep]) -> [ToolStep] {
        var updated = AgentRunLogic.adding(ToolStep(call: call, result: nil), to: steps)
        for index in updated.indices where updated[index].id == call.id { updated[index].children = children }
        return updated
    }

    /// A subagent step still running when the reply ended was cut off, like a call of the reply itself.
    static func settled(_ steps: [ToolStep]) -> [ToolStep] {
        steps.map { step in
            var settled = step
            settled.children = step.children?.map { child in
                guard child.result == nil else { return child }
                var cut = child
                cut.result = ToolResult(callID: child.call.id, name: child.call.name, text: ToolRowLogic.cancelledText, isError: true)
                return cut
            }
            return settled
        }
    }

    /// The tokens the reply's calls used on their own requests (its subagents').
    static func spentTokens(_ steps: [ToolStep]) -> (prompt: Int, completion: Int) {
        steps.reduce((prompt: 0, completion: 0)) { sum, step in
            (sum.prompt + (step.result?.promptTokens ?? 0), sum.completion + (step.result?.completionTokens ?? 0))
        }
    }

    /// `metadata` with `tokens` added to its own counts.
    static func adding(_ tokens: (prompt: Int, completion: Int), to metadata: ResponseMetadata) -> ResponseMetadata {
        guard tokens.prompt + tokens.completion > 0 else { return metadata }
        var total = metadata
        total.promptTokens = (metadata.promptTokens ?? 0) + tokens.prompt
        total.completionTokens = (metadata.completionTokens ?? 0) + tokens.completion
        return total
    }
}
