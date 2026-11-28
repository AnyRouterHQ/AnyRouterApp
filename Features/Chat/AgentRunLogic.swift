import Foundation

/// The step boundaries of a run as the chat sees them (agent design 1.3): a tool call starts `act`, its result ends the
/// round and the model generates again. Also the resume rules for the steps of a run after a relaunch.
enum AgentRunLogic {
    struct Checkpoint: Equatable, Sendable {
        var node: AgentNode
        var round: Int
    }

    /// The checkpoint after `delta`, or nil when it is no step boundary (text, reasoning, usage).
    static func checkpoint(after delta: ChatDelta, from current: Checkpoint) -> Checkpoint? {
        switch delta {
        case .toolCall: current.node == .act ? nil : Checkpoint(node: .act, round: current.round)
        case .toolResult: current.node == .act ? Checkpoint(node: .generate, round: current.round + 1) : nil
        default: nil
        }
    }

    /// At launch a run that was generating or running a tool cannot go on by itself: generation needs the app in the
    /// foreground, and a cloud request must not be paid for again without the user. A run that waits for the user keeps
    /// waiting, so its approval card comes back.
    static func afterRelaunch(_ status: AgentRunStatus) -> AgentRunStatus {
        status == .running ? .interrupted : status
    }

    /// The steps after a relaunch (agent design 1.3). An approved write or external call with no result may have run, so
    /// it does not run again: it gets `ToolRowLogic.unfinishedText`, which also tells the model it may not have finished.
    /// A call whose class is unknown counts as a write. Every other step is left as it is.
    static func settled(_ steps: [ToolStep], sideEffects: [String: ToolSideEffect]) -> [ToolStep] {
        steps.map { step in
            guard step.result == nil, let approval = step.approval, approval != .deny,
                sideEffects[step.call.id].map(\.isRead) != true
            else { return step }
            var settled = step
            settled.result = ToolResult(callID: step.call.id, name: step.call.name, text: ToolRowLogic.unfinishedText, isError: true)
            return settled
        }
    }

    /// The answers of approved calls that have no result, by call id: such a call runs again without asking again.
    static func decided(_ steps: [ToolStep]) -> [String: ToolDecision] {
        var decided: [String: ToolDecision] = [:]
        for step in steps where step.result == nil {
            if let approval = step.approval, approval != .deny { decided[step.call.id] = approval }
        }
        return decided
    }

    /// The rounds to go on from: each saved round with the results its steps hold. A round's results are those of its
    /// leading calls that have one; the loop runs the rest. The last saved round is the one the run stopped in. Nil when
    /// no round was saved (Apple's framework loop saves none).
    static func resume(_ state: AgentRunState, steps: [ToolStep]) -> AgentResume? {
        guard let last = state.rounds.last else { return nil }
        var results: [String: ToolResult] = [:]
        for step in steps {
            if let result = step.result { results[step.id] = result }
        }
        func round(_ saved: AgentSavedRound) -> AgentRound {
            let answered = saved.calls.prefix(while: { results[$0.id] != nil }).compactMap { results[$0.id] }
            return AgentRound(text: saved.text, calls: saved.calls, results: answered)
        }
        return AgentResume(rounds: state.rounds.dropLast().map(round), pending: round(last))
    }

    /// `step` added at the end, unless a step with its id is there already: a resumed run announces its waiting call
    /// again, and an answer can be noted before its call's row arrives.
    static func adding(_ step: ToolStep, to steps: [ToolStep]) -> [ToolStep] {
        steps.contains { $0.id == step.id } ? steps : steps + [step]
    }

    /// `steps` with the user's answer on `call`'s step, which is added when its row has not arrived yet.
    static func approving(_ call: ToolCall, _ decision: ToolDecision, in steps: [ToolStep]) -> [ToolStep] {
        var updated = adding(ToolStep(call: call, result: nil), to: steps)
        for index in updated.indices where updated[index].id == call.id { updated[index].approval = decision }
        return updated
    }
}
