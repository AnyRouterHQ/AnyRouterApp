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

    /// An unknown raw value reads as finish, the node that runs nothing.
    var node: AgentNode {
        get { AgentNode(rawValue: nodeRaw) ?? .finish }
        set { nodeRaw = newValue.rawValue }
    }
}
