import Foundation

/// The skill a device engine gets for one question (agent design 4.2, unit K1). Apple, GGUF and MLX chats have no
/// `read_skill` (the four-tool window), so the app picks before the send: one enabled skill whose name and description
/// share at least two content words with the question, and only when its steps fit the device skills budget. An ordinary
/// question shares fewer and picks nothing.
enum SkillPickLogic {
    static let minimumSharedWords = 2

    /// The guidance text for the best matching skill that fits `budget` tokens, or nil. The most shared words win; a tie
    /// goes to the skill earlier in the list (the bundled ones come first). A skill too long for the budget is passed over.
    static func pick(_ question: String?, from skills: [Skill], budget: Int) -> String? {
        guard let question else { return nil }
        let asked = MemoryRecallLogic.contentTerms(question)
        let matches = skills.enumerated().compactMap { index, skill -> (shared: Int, index: Int, skill: Skill)? in
            let shared = asked.intersection(MemoryRecallLogic.contentTerms(skill.name + " " + skill.description)).count
            return shared >= minimumSharedWords ? (shared, index, skill) : nil
        }
        .sorted { $0.shared != $1.shared ? $0.shared > $1.shared : $0.index < $1.index }
        return matches.map { SkillLogic.guidance($0.skill) }.first { TokenCountLogic.estimate($0) <= budget }
    }
}
