import Foundation

/// `propose_skill`: the model suggests a skill; the reply shows it with Save and Discard. The call itself saves nothing, so
/// it runs without a second question: the user's Save is the approval.
struct ProposeSkillTool: BuiltInTool {
    let store: SkillProposalStore
    let sideEffect = ToolSideEffect.write
    let undoesInsteadOfAsking = true
    let name = SkillProposalLogic.toolName
    let title = "Propose skill"
    let summary = "Suggest a skill for you to approve"
    let description = SkillProposalLogic.toolDescription
    let schema = JSONSchema(parsing: SkillProposalLogic.toolSchema)

    func run(_ arguments: JSONValue) async throws -> String { try await store.propose(arguments) }
}
