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
}
