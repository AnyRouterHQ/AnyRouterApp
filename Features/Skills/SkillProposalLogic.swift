import Foundation

/// The words and rules of the cloud model's `propose_skill` tool (agent design 4.2, unit K2). The model writes a skill;
/// the user decides. Nothing is saved until the user presses Save on the proposal in the reply.
enum SkillProposalLogic {
    static let toolName = "propose_skill"
    static let toolDescription = """
        Propose a new skill for the user to approve, only after a task that took three or more tool calls and went well. \
        Write steps another run can follow: lessons, not a log of this chat. Never include personal data, keys or the \
        user's private text. The user reads the full text and decides; nothing is saved unless they press Save. \
        A skill is guidance only: it cannot allow a tool.
        """
    static let toolSchema = #"{"type":"object","properties":{"name":{"type":"string","description":"Lowercase words joined by hyphens, like trip-planner"},"description":{"type":"string","description":"One line: what the skill is for and when to use it"},"body":{"type":"string","description":"The steps, at most 8000 characters"}},"required":["name","description","body"]}"#
    static let maxPerReply = 3
    static let accepted = "Proposed. The user will read it and may save or discard it. It is not saved yet; do not tell the user it is."

    /// The checked skill text from the call's arguments. A refusal says what to fix, so the model can try again.
    static func draft(from arguments: JSONValue) throws -> SkillDraft {
        guard let name = arguments["name"]?.string, let description = arguments["description"]?.string,
              let body = arguments["body"]?.string else {
            throw BuiltInToolError("Give all three: name, description and body.")
        }
        do {
            return try SkillLibraryLogic.validate(SkillDraft(name: name, description: description, body: body))
        } catch {
            throw BuiltInToolError(error.localizedDescription)
        }
    }

    /// The row's words for each state.
    static func title(of proposal: SkillProposal) -> String {
        switch proposal.state {
        case .pending: String(localized: "Skill proposed: \(proposal.draft.name)")
        case .saved: String(localized: "Skill saved: \(proposal.draft.name)")
        case .discarded: String(localized: "Skill discarded: \(proposal.draft.name)")
        }
    }
}
