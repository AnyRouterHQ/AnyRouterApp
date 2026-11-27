import Foundation

/// One piece of an assistant turn, in the order it is drawn. Each case has one view (see PLAN.md, Reply parts).
enum ReplyPart: Equatable, Identifiable {
    case reasoning(ReasoningTrace, isStreaming: Bool)
    case toolStep([ToolStep])
    case text(String)
    case file(ChatAttachment)
    case image(ChatAttachment)

    var id: String {
        switch self {
        case .reasoning: "reasoning"
        case .toolStep: "tools"
        case .text: "text"
        case .file(let attachment): "file-\(attachment.id)"
        case .image(let attachment): "image-\(attachment.id)"
        }
    }
}

enum ReplyParts {
    /// The parts of one reply: what the model thought, the tools it used, its answer, then the files and photos it carries.
    /// Empty parts are left out.
    /// The model is still thinking while the reply streams and its reasoning has no end yet.
    static func make(
        reasoning: ReasoningTrace?, steps: [ToolStep], content: String, isStreaming: Bool, attachments: [ChatAttachment] = []
    ) -> [ReplyPart] {
        var parts: [ReplyPart] = []
        if let reasoning { parts.append(.reasoning(reasoning, isStreaming: isStreaming && reasoning.durationMs == nil)) }
        if !steps.isEmpty { parts.append(.toolStep(steps)) }
        if !content.isEmpty { parts.append(.text(content)) }
        parts += attachments.map { $0.kind == .image ? .image($0) : .file($0) }
        return parts
    }
}
