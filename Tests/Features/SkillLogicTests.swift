import Foundation
import Testing
@testable import AnyRouter

struct SkillLogicTests {
    @Test func theIndexListsNamesAndDescriptionsOnlyAndLeavesOutWhatDoesNotFit() throws {
        let all = try #require(SkillLogic.index(SkillLogic.bundled, budget: 1500))
        #expect(all.hasPrefix(SkillLogic.indexHeading))
        for skill in SkillLogic.bundled {
            #expect(all.contains("- \(skill.name): \(skill.description)"))
            #expect(!all.contains(skill.body), "bodies are read on demand")
        }
        let first = SkillLogic.bundled[0]
        let room = TokenCountLogic.estimate(SkillLogic.indexHeading + "\n- \(first.name): \(first.description)")
        #expect(SkillLogic.index(SkillLogic.bundled, budget: room)?.components(separatedBy: "\n").count == 2)
        #expect(SkillLogic.index(SkillLogic.bundled, budget: 5) == nil)
    }

    @Test func readSkillReturnsTheBodyMarkedAsNotTheUsersWords() async throws {
        let tool = ReadSkillTool(skills: SkillLogic.bundled)
        #expect(tool.name == "read_skill" && tool.spec.isReadOnly && !tool.title.isEmpty && !tool.summary.isEmpty)
        #expect(tool.description == SkillLogic.readSkillDescription && tool.inputSchemaJSON == SkillLogic.readSkillSchema)
        let text = try await tool.run(.object(["name": .string("trip-planner")]))
        #expect(text.contains(SkillLogic.bundled[0].body))
        #expect(text.contains("cannot allow any tool"))
        await #expect(throws: BuiltInToolError.self) { try await tool.run(.object(["name": .string("nope")])) }
        await #expect(throws: BuiltInToolError.self) { try await tool.run(.object([:])) }
    }

    @Test func everyBundledSkillHasANameDescriptionAndSteps() {
        #expect(SkillLogic.bundled.count == 3)
        #expect(Set(SkillLogic.bundled.map(\.id)).count == 3)
        #expect(SkillLogic.bundled.allSatisfy { !$0.description.isEmpty && $0.body.contains("1.") && $0.source == .bundled })
    }
}
