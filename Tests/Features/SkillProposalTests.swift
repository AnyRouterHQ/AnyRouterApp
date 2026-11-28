import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// `propose_skill`: the model proposes, the user decides, and nothing reaches the skill library without Save.
@MainActor
struct SkillProposalTests {
    @MainActor private struct Rig {
        let context: ModelContext
        let reply: MessageRecord
        var proposals: SkillProposalStore { SkillProposalStore(context: context, reply: reply) }
        var library: SkillStore { SkillStore(context: context) }
    }

    private func rig() throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let reply = MessageRecord(role: .assistant, content: "", modelID: "anyrouter/auto")
        context.insert(reply)
        return Rig(context: context, reply: reply)
    }

    private func arguments(_ name: String = "bill-splitter", description: String = "Split a bill between friends.", body: String = "1. Ask who paid.") -> JSONValue {
        .object(["name": .string(name), "description": .string(description), "body": .string(body)])
    }

    private func refusal(_ work: () throws -> String) -> String? {
        do { _ = try work() } catch { return (error as? BuiltInToolError)?.message }
        return nil
    }

    @Test func aProposalWaitsOnTheReplyAndSavesNothing() throws {
        let r = try rig()
        let answer = try r.proposals.propose(arguments(description: "Split\na bill."))
        #expect(answer == SkillProposalLogic.accepted && answer.contains("not saved yet"))
        let proposal = try #require(r.reply.skillProposals.first)
        #expect(proposal.state == .pending)
        #expect(proposal.draft == SkillDraft(name: "bill-splitter", description: "Split a bill.", body: "1. Ask who paid."))
        #expect(try r.library.all().isEmpty, "a proposal is not a skill until the user presses Save")
        #expect(try r.library.enabledSkills().isEmpty)
    }

    @Test func saveStoresTheSkillAsTheUsersOwnAndMarksTheProposal() throws {
        let r = try rig()
        try r.proposals.propose(arguments())
        let id = try #require(r.reply.skillProposals.first?.id)
        try r.proposals.save(id)
        #expect(r.reply.skillProposals.first?.state == .saved)
        let saved = try #require(try r.library.all().first)
        #expect(saved.name == "bill-splitter" && saved.source == .proposed && saved.enabled && saved.sourceRef == nil)
        try r.proposals.save(id)
        try r.proposals.discard(id)
        #expect(try r.library.all().count == 1, "a saved proposal cannot be saved twice or discarded")
        #expect(r.reply.skillProposals.first?.state == .saved)
    }

    @Test func discardKeepsNothingAndCannotBeUndoneBySave() throws {
        let r = try rig()
        try r.proposals.propose(arguments())
        let id = try #require(r.reply.skillProposals.first?.id)
        try r.proposals.discard(id)
        #expect(r.reply.skillProposals.first?.state == .discarded)
        try r.proposals.save(id)
        #expect(try r.library.all().isEmpty && r.reply.skillProposals.first?.state == .discarded)
        try r.proposals.save(UUID())
        try r.proposals.discard(UUID())
        #expect(r.reply.skillProposals.count == 1)
    }

    @Test func aSaveTheLibraryRefusesLeavesTheProposalPending() throws {
        let r = try rig()
        try r.proposals.propose(arguments())
        try r.library.add(SkillDraft(name: "bill-splitter", description: "Mine.", body: "1. Mine."), source: .imported)
        let id = try #require(r.reply.skillProposals.first?.id)
        #expect(throws: SkillStoreError.duplicate("bill-splitter")) { try r.proposals.save(id) }
        #expect(r.reply.skillProposals.first?.state == .pending)
        #expect(try r.library.all().count == 1)
    }

    @Test func textThatBreaksTheRulesIsRefusedWithTheReasonAndLeavesNoRow() throws {
        let r = try rig()
        #expect(refusal { try r.proposals.propose(self.arguments("Bad Name")) } == SkillIssue.badName.errorDescription)
        #expect(refusal { try r.proposals.propose(self.arguments("trip-planner")) } == SkillIssue.reservedName.errorDescription)
        #expect(refusal { try r.proposals.propose(self.arguments(description: " ")) } == SkillIssue.emptyDescription.errorDescription)
        #expect(refusal { try r.proposals.propose(self.arguments(body: String(repeating: "x", count: 8_001))) } == SkillIssue.bodyTooLong.errorDescription)
        #expect(refusal { try r.proposals.propose(.object(["name": .string("bill-splitter")])) } == "Give all three: name, description and body.")
        #expect(r.reply.skillProposals.isEmpty)
    }

    @Test func aNameTheUserHasOrAlreadyProposedIsRefusedButADiscardedOneMayComeBack() throws {
        let r = try rig()
        try r.library.add(SkillDraft(name: "owned-one", description: "Mine.", body: "1. Mine."), source: .hub, sourceRef: "h/owned-one")
        #expect(refusal { try r.proposals.propose(self.arguments("owned-one")) } == SkillStoreError.duplicate("owned-one").errorDescription)
        try r.proposals.propose(arguments("fresh-idea"))
        #expect(refusal { try r.proposals.propose(self.arguments("fresh-idea")) } == SkillStoreError.duplicate("fresh-idea").errorDescription)
        try r.proposals.discard(try #require(r.reply.skillProposals.first?.id))
        try r.proposals.propose(arguments("fresh-idea"))
        #expect(r.reply.skillProposals.count == 2)
    }

    @Test func aReplyHoldsAtMostThreeProposals() throws {
        let r = try rig()
        for name in ["one-a", "two-b", "three-c"] { try r.proposals.propose(arguments(name)) }
        #expect(refusal { try r.proposals.propose(self.arguments("four-d")) }?.contains("3 proposals") == true)
        #expect(r.reply.skillProposals.count == 3)
    }

    @Test func rowTitlesFollowTheState() {
        let draft = SkillDraft(name: "bill-splitter", description: "D.", body: "B.")
        let titles = [SkillProposal.State.pending, .saved, .discarded].map { SkillProposalLogic.title(of: SkillProposal(draft: draft, state: $0)) }
        #expect(titles == ["Skill proposed: bill-splitter", "Skill saved: bill-splitter", "Skill discarded: bill-splitter"])
    }

    @Test func proposalsRoundTripOnTheReplyAndAnUnreadableValueReadsAsNone() throws {
        let r = try rig()
        #expect(r.reply.skillProposals.isEmpty && r.reply.skillProposalsData == nil)
        let proposal = SkillProposal(draft: SkillDraft(name: "bill-splitter", description: "D.", body: "B."), state: .saved)
        r.reply.skillProposals = [proposal]
        #expect(r.reply.skillProposals == [proposal])
        r.reply.skillProposals = []
        #expect(r.reply.skillProposalsData == nil)
        r.reply.skillProposalsData = Data("not json".utf8)
        #expect(r.reply.skillProposals.isEmpty)
    }

    @Test func theToolRunsWithoutASecondQuestionBecauseSaveIsTheApproval() async throws {
        final class Asked: ToolApproving, @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
                lock.withLock { count += 1 }
                return .deny
            }
        }
        let r = try rig()
        let tool = ProposeSkillTool(store: r.proposals)
        #expect(tool.name == "propose_skill" && tool.sideEffect == .write && tool.undoesInsteadOfAsking)
        #expect(tool.spec.name == SkillProposalLogic.toolName && tool.description == SkillProposalLogic.toolDescription)
        #expect(tool.schema == JSONSchema(parsing: SkillProposalLogic.toolSchema) && !tool.title.isEmpty && !tool.summary.isEmpty)
        #expect(JSONValue.parse(SkillProposalLogic.toolSchema)?["required"]?.array?.count == 3)
        let asked = Asked()
        let host = AgentToolHost(builtIns: [tool], search: nil, mcp: nil, approver: asked)
        let json = #"{"name":"bill-splitter","description":"Split a bill.","body":"1. Ask."}"#
        let result = await host.execute(ToolCall(id: "c", name: "propose_skill", argumentsJSON: json))
        #expect(!result.isError && result.text == SkillProposalLogic.accepted)
        let stored = try r.library.all()
        #expect(asked.count == 0 && r.reply.skillProposals.count == 1 && stored.isEmpty)
        let refused = await host.execute(ToolCall(id: "d", name: "propose_skill", argumentsJSON: #"{"name":"X"}"#))
        #expect(refused.isError)
    }
}
