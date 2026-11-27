import Foundation

/// The parts of one request (agent design 3.2). Instructions and the profile are the stable start of every request;
/// the summary, the turns and this turn's context come after them and change.
enum PromptSection: String, CaseIterable, Sendable {
    case instructions, profile, summary, turns, context
}

/// Tokens the sections with a cap may take on one model (agent design 3.3). The turns take what is left.
struct PromptBudget: Equatable, Sendable {
    var profile: Int
    var memoryHits: Int

    static func forModel(_ model: ModelDescriptor) -> PromptBudget {
        switch model.source {
        case .apple: PromptBudget(profile: 120, memoryHits: 150)
        case .gguf, .mlx: (model.contextLength ?? 0) > 4096 ? PromptBudget(profile: 200, memoryHits: 300) : PromptBudget(profile: 120, memoryHits: 150)
        case .anyrouter: PromptBudget(profile: 500, memoryHits: 1500)
        }
    }
}

/// One request as the engine gets it, and the tokens each section took: the context meter and the compaction trigger
/// read `total`.
struct AssembledPrompt: Equatable, Sendable {
    var systemPrompt: String?
    var messages: [ChatMessage]
    var used: [PromptSection: Int]

    var total: Int { used.values.reduce(0, +) }
}

/// Builds every chat request from its sections, in one order. The system message holds only what rarely changes, so a
/// compaction no longer rewrites it. The summary and this turn's context are merged into user messages, never added as
/// messages of their own, so roles still alternate for chat templates that require it.
enum PromptAssembler {
    static let summaryHeading = "Earlier in this conversation (older messages were shortened into this summary):"
    /// A few tokens per message for its role.
    static let perMessageTokens = 4

    static func assemble(
        instructions: String?, profile: String?, summary: String?, turns: [ChatMessage], context: String?
    ) -> AssembledPrompt {
        let system = [instructions, profile].compactMap { $0 }.joined(separator: "\n\n")
        let summaryText = summary.map { summaryHeading + "\n" + $0 }
        var messages = turns
        if let summaryText, let first = messages.firstIndex(where: { $0.role == .user }) {
            messages[first].content = summaryText + "\n\n" + messages[first].content
        }
        if let context, let last = messages.lastIndex(where: { $0.role == .user }) {
            messages[last].content = context + "\n\n" + messages[last].content
        }
        let used: [PromptSection: Int] = [
            .instructions: tokens(instructions),
            .profile: tokens(profile),
            .summary: tokens(summaryText),
            .turns: turns.reduce(0) { $0 + TokenCountLogic.estimate($1.content) + perMessageTokens },
            .context: tokens(context),
        ]
        return AssembledPrompt(systemPrompt: system.isEmpty ? nil : system, messages: messages, used: used)
    }

    private static func tokens(_ text: String?) -> Int {
        text.map(TokenCountLogic.estimate) ?? 0
    }
}
