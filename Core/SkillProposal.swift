import Foundation

/// A skill the model proposed in a reply, waiting for the user (agent design 4.2, unit K2). It lives on the reply as JSON
/// (`MessageRecord.skillProposals`) and reaches the skill library only when the user presses Save.
struct SkillProposal: Codable, Equatable, Sendable, Identifiable {
    enum State: Codable, Equatable, Sendable {
        case pending, saved, discarded
    }

    var id = UUID()
    var draft: SkillDraft
    var state = State.pending
}
