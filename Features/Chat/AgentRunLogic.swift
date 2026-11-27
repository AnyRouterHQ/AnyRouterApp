import Foundation

/// The step boundaries of a run as the chat sees them today (agent design 1.3): a tool call starts `act`, its result
/// ends the round and the model generates again. The app loop (unit G3) will own these steps itself.
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

    /// At launch a run the app was still in cannot go on by itself: generation needs the app in the foreground, and a
    /// cloud request must not be paid for again without the user.
    static func afterRelaunch(_ status: AgentRunStatus) -> AgentRunStatus {
        status == .running || status == .awaitingApproval ? .interrupted : status
    }
}
