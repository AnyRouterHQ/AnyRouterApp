import Foundation
import SwiftData

/// Records the skills the model proposes in one reply, and what the user does with them. Only `save` reaches the skill
/// library, and it runs only from the Save button of the proposal's row.
@MainActor
final class SkillProposalStore {
    private let context: ModelContext
    private let reply: MessageRecord

    init(context: ModelContext, reply: MessageRecord) {
        self.context = context
        self.reply = reply
    }

    /// Adds a pending proposal to the reply and returns what the model reads back. Text that breaks the skill rules, a name
    /// the user already has, a second proposal of the same name and a fourth proposal in one reply are refused.
    @discardableResult
    func propose(_ arguments: JSONValue) throws -> String {
        let draft = try SkillProposalLogic.draft(from: arguments)
        let proposals = reply.skillProposals
        guard proposals.count < SkillProposalLogic.maxPerReply else {
            throw BuiltInToolError("This reply already has \(SkillProposalLogic.maxPerReply) proposals. Do not propose more.")
        }
        guard try !SkillStore(context: context).all().contains(where: { $0.name == draft.name }),
              !proposals.contains(where: { $0.draft.name == draft.name && $0.state != .discarded }) else {
            throw BuiltInToolError(SkillStoreError.duplicate(draft.name).localizedDescription)
        }
        reply.skillProposals = proposals + [SkillProposal(draft: draft)]
        try context.save()
        return SkillProposalLogic.accepted
    }

    /// The Save button: stores the skill as the user's own (switched on) and marks the proposal saved. A proposal that is not
    /// pending, or that the library refuses, stays as it was.
    func save(_ id: UUID) throws {
        guard let proposal = pending(id) else { return }
        try SkillStore(context: context).add(proposal.draft, source: .proposed)
        try mark(id, .saved)
    }

    func discard(_ id: UUID) throws {
        guard pending(id) != nil else { return }
        try mark(id, .discarded)
    }

    private func pending(_ id: UUID) -> SkillProposal? {
        reply.skillProposals.first { $0.id == id && $0.state == .pending }
    }

    private func mark(_ id: UUID, _ state: SkillProposal.State) throws {
        var proposals = reply.skillProposals
        if let index = proposals.firstIndex(where: { $0.id == id }) { proposals[index].state = state }
        reply.skillProposals = proposals
        try context.save()
    }
}
