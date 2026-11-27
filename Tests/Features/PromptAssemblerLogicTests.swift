import Foundation
import Testing
@testable import AnyRouter

struct PromptAssemblerLogicTests {
    private let turns = [
        ChatMessage(role: .user, content: "Question 4"), ChatMessage(role: .assistant, content: "Reply."),
        ChatMessage(role: .user, content: "Question 5"),
    ]

    @Test func theSystemMessageHoldsInstructionsThenProfileAndNothingThatChanges() {
        let plain = PromptAssembler.assemble(instructions: "Be brief.", profile: "P", summary: nil, turns: turns, context: nil)
        let later = PromptAssembler.assemble(instructions: "Be brief.", profile: "P", summary: "S", turns: turns, context: "C")
        #expect(plain.systemPrompt == "Be brief.\n\nP")
        #expect(later.systemPrompt == plain.systemPrompt, "a summary or a recall never changes the start of the request")
        #expect(PromptAssembler.assemble(instructions: nil, profile: "P", summary: nil, turns: turns, context: nil).systemPrompt == "P")
        #expect(PromptAssembler.assemble(instructions: nil, profile: nil, summary: nil, turns: turns, context: nil).systemPrompt == nil)
        let withSkills = PromptAssembler.assemble(instructions: "Be brief.", profile: "P", skills: "S", summary: nil, turns: turns, context: nil)
        #expect(withSkills.systemPrompt == "Be brief.\n\nP\n\nS")
        #expect(withSkills.used[.skills] == TokenCountLogic.estimate("S"))
    }

    @Test func theSummaryGoesWithTheFirstQuestionAndTheContextWithTheLastSoRolesStillAlternate() {
        let prompt = PromptAssembler.assemble(instructions: nil, profile: nil, summary: "They talked about actors.", turns: turns, context: "Things the user told you before:\n- X")
        #expect(prompt.messages.map(\.role) == [.user, .assistant, .user])
        #expect(prompt.messages[0].content == PromptAssembler.summaryHeading + "\nThey talked about actors.\n\nQuestion 4")
        #expect(prompt.messages[1].content == "Reply.")
        #expect(prompt.messages[2].content == "Things the user told you before:\n- X\n\nQuestion 5")
        let answerOnly = [ChatMessage(role: .assistant, content: "Hello")]
        #expect(PromptAssembler.assemble(instructions: nil, profile: nil, summary: "S", turns: answerOnly, context: "C").messages == answerOnly)
    }

    @Test func theReportCountsEverySectionAndTheirSum() {
        let prompt = PromptAssembler.assemble(instructions: "Be brief.", profile: nil, summary: "S", turns: turns, context: nil)
        #expect(prompt.used[.instructions] == TokenCountLogic.estimate("Be brief."))
        #expect(prompt.used[.profile] == 0)
        #expect(prompt.used[.summary] == TokenCountLogic.estimate(PromptAssembler.summaryHeading + "\nS"))
        #expect(prompt.used[.turns] == turns.reduce(0) { $0 + TokenCountLogic.estimate($1.content) + PromptAssembler.perMessageTokens })
        #expect(prompt.used[.context] == 0)
        #expect(prompt.total == PromptSection.allCases.reduce(0) { $0 + (prompt.used[$1] ?? 0) })
    }

    @Test func theBudgetFollowsTheEngineWindow() {
        func model(_ source: ModelSource, _ context: Int?) -> ModelDescriptor {
            ModelDescriptor(id: "m", source: source, displayName: "m", contextLength: context, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        }
        #expect(PromptBudget.forModel(model(.apple, 4096)) == PromptBudget(profile: 120, memoryHits: 150))
        #expect(PromptBudget.forModel(model(.gguf, nil)) == PromptBudget(profile: 120, memoryHits: 150))
        #expect(PromptBudget.forModel(model(.gguf, 4096)) == PromptBudget(profile: 120, memoryHits: 150))
        #expect(PromptBudget.forModel(model(.mlx, 8192)) == PromptBudget(profile: 200, memoryHits: 300))
        #expect(PromptBudget.forModel(model(.anyrouter, 128_000)) == PromptBudget(profile: 500, memoryHits: 1500, skills: 1500))
    }
}
