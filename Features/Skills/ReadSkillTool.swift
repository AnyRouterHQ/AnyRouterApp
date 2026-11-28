import Foundation

/// `read_skill`: the full steps of one skill. It lives apart from `SkillLogic.swift` because the coverage gate counts the
/// property initializers of a tool struct as lines that never run.
struct ReadSkillTool: BuiltInTool {
    let skills: [Skill]
    let name = SkillLogic.readSkillName
    let title = "Skills"
    let summary = "Steps for common tasks"
    let description = SkillLogic.readSkillDescription
    let inputSchemaJSON = SkillLogic.readSkillSchema

    func run(_ arguments: JSONValue) async throws -> String { try SkillLogic.read(arguments, from: skills) }
}
