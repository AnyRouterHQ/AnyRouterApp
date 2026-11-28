import Foundation

/// What happened at a node of a run (agent design 1.2). The loop keeps the data; the graph needs only the kind.
enum AgentEvent: Equatable, CaseIterable, Sendable {
    case fits, overBudget, compacted, compactFailed, calls, noCalls, needsApproval, decided, resultsIn, failed, stopped
}

/// The step graph of a run as a pure function, so tests drive it without a model.
enum AgentGraph {
    /// The node after `node` on `event`. `round` counts the tool rounds done. A round at or past `maxRounds` was asked
    /// with tools off, so calls it still proposes end the run instead of running (the last round answers, as before
    /// G3). A pair the table does not list ends the run.
    static func next(_ node: AgentNode, on event: AgentEvent, round: Int, maxRounds: Int) -> AgentNode {
        switch (node, event) {
        case (.finish, _), (.remember, _): return .remember
        case (_, .failed), (_, .stopped): return .finish
        case (.assemble, .fits), (.compact, .compactFailed): return .generate
        case (.assemble, .overBudget): return .compact
        case (.compact, .compacted), (.act, .resultsIn): return .assemble
        case (.generate, .calls): return round < maxRounds ? .act : .finish
        case (.act, .needsApproval): return .approve
        case (.approve, .decided): return .act
        default: return .finish
        }
    }
}
