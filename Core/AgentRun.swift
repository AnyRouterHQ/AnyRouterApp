import Foundation
import SwiftData

/// Where one reply's run stands (agent design 1.1).
enum AgentRunStatus: String, Codable, CaseIterable, Sendable {
    case running, awaitingApproval, finished, failed, cancelled, interrupted
}

/// The step a run takes next (agent design 1.2).
enum AgentNode: String, Codable, CaseIterable, Sendable {
    case assemble, compact, generate, act, approve, finish, remember
}

/// What a run keeps besides its node and round (agent design 1.1). Text, steps and reasoning stay on the reply.
struct AgentRunState: Codable, Equatable, Sendable {
    /// Each tool round as the model asked for it, including calls that had not started when the app closed: the
    /// steps on the reply hold only calls that started.
    var rounds: [AgentSavedRound] = []
    /// The side-effect class of each call the user was asked about, by call id, so a relaunch knows which approved
    /// calls must not run twice.
    var sideEffects: [String: ToolSideEffect] = [:]
}

/// One tool round: the text the model wrote with it, as the next request carries it, and every call it asked for.
struct AgentSavedRound: Codable, Equatable, Sendable {
    var text: String
    var calls: [ToolCall]
}

/// One reply's run, saved at step boundaries, never per token, so a relaunch knows where each unfinished run stopped.
/// Text, steps and reasoning stay on the reply's `MessageRecord`. A run that ends is deleted: only an unfinished one
/// has anything to resume.
@Model final class AgentRunRecord {
    @Attribute(.unique) var id: UUID
    var threadID: UUID
    /// The assistant message this run writes into.
    var messageID: UUID
    var modelID: String
    var statusRaw: String
    var nodeRaw: String
    /// Tool rounds finished so far.
    var round: Int
    var startedAt: Date
    var updatedAt: Date
    /// `AgentRunState` as JSON. Optional so existing stores migrate.
    var stateData: Data?

    init(id: UUID = UUID(), threadID: UUID, messageID: UUID, modelID: String, now: Date = Date()) {
        self.id = id
        self.threadID = threadID
        self.messageID = messageID
        self.modelID = modelID
        self.statusRaw = AgentRunStatus.running.rawValue
        self.nodeRaw = AgentNode.assemble.rawValue
        self.round = 0
        self.startedAt = now
        self.updatedAt = now
    }

    /// An unknown raw value reads as interrupted: a run this build cannot place is not resumed.
    var status: AgentRunStatus {
        get { AgentRunStatus(rawValue: statusRaw) ?? .interrupted }
        set { statusRaw = newValue.rawValue }
    }

    /// Data this build cannot read is an empty state: the run then has no rounds to rebuild.
    var state: AgentRunState {
        get { stateData.flatMap { try? JSONDecoder().decode(AgentRunState.self, from: $0) } ?? AgentRunState() }
        set { stateData = try? JSONEncoder().encode(newValue) }
    }

    /// An unknown raw value reads as finish, the node that runs nothing.
    var node: AgentNode {
        get { AgentNode(rawValue: nodeRaw) ?? .finish }
        set { nodeRaw = newValue.rawValue }
    }
}
