import SwiftUI

/// One message row: user text in a rounded bubble, assistant reply as plain markdown with actions.
struct MessageRow: View {
    let message: MessageRecord
    let isStreamingThis: Bool
    let showsRegenerate: Bool
    var onRegenerate: () -> Void
    /// "Switched to <model>" above a reply written by a different model than the one before.
    var switchNote: String?
    /// Setting "Show response details": cost and speed under the reply.
    var showsDetails: Bool
    /// A local model that is loading: shown instead of the typing dots until its first token.
    var loadingModelName: String?

    init(message: MessageRecord, isStreamingThis: Bool, showsRegenerate: Bool,
         onRegenerate: @escaping () -> Void, switchNote: String? = nil, showsDetails: Bool = true,
         loadingModelName: String? = nil) {
        self.loadingModelName = loadingModelName
        self.showsDetails = showsDetails
        self.message = message
        self.isStreamingThis = isStreamingThis
        self.showsRegenerate = showsRegenerate
        self.onRegenerate = onRegenerate
        self.switchNote = switchNote
    }

    var body: some View {
        switch message.role {
        case .user: userRow
        case .assistant: assistantRow
        case .system: EmptyView()
        }
    }

    private var userRow: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty { MessageAttachments(attachments: message.attachments) }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    private var assistantRow: some View {
        // Body time of an assistant row. The MarkdownUI subtree below builds its layout later, outside this interval.
        let signpost = Perf.signposter.beginInterval("row.assistant")
        defer { Perf.signposter.endInterval("row.assistant", signpost) }
        let steps = message.toolSteps
        let parts = ReplyParts.make(
            reasoning: message.reasoning, steps: steps, content: message.content, isStreaming: isStreamingThis)
        let answerStarted = !message.content.isEmpty
        let thinking = parts.contains { if case .reasoning(_, true) = $0 { true } else { false } }
        return VStack(alignment: .leading, spacing: 6) {
            if let switchNote {
                Text(switchNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("switch-note")
            }
            ForEach(parts) { part in
                switch part {
                case .reasoning(let trace, let isStreaming): ReasoningRow(trace: trace, isStreaming: isStreaming)
                case .toolStep(let calls): ToolChainView(steps: calls, answerStarted: answerStarted)
                case .text(let text): MarkdownReply(text: text)
                }
            }
            // The model is loading, or has not started the answer, and nothing else on the row says it is working.
            if isStreamingThis && !answerStarted && !thinking && !steps.contains(where: { $0.result == nil }) {
                if let loadingModelName {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading \(loadingModelName)…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("model-loading")
                } else {
                    TypingDots()
                        .padding(.vertical, 8)
                }
            }
            if let footer = ReplyFooter.make(
                content: message.content, isStreaming: isStreamingThis, showsRegenerate: showsRegenerate,
                showsDetails: showsDetails, requestedName: message.modelName, requestedID: message.modelID,
                metadata: message.metadata, steps: steps) {
                ReplyFooterRow(message: message, footer: footer, onRegenerate: onRegenerate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The SF Symbols "typing" animation, shown before the first token arrives. The system skips it for Reduce Motion.
struct TypingDots: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            .accessibilityLabel("Thinking")
    }
}
