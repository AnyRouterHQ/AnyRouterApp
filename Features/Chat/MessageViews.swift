import SwiftData
import SwiftUI
import UIKit

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
    /// What the model is doing before the answer starts, when it is not just waiting: "Shortening the conversation…".
    var statusNote: String?
    /// Retry, Sign in, Choose another model, … from a failed reply.
    var onFailureAction: (ReplyFailure.Action) -> Void
    /// A cloud model can take over a device reply that failed ("Ask a cloud model").
    var canAskCloud: Bool
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    init(message: MessageRecord, isStreamingThis: Bool, showsRegenerate: Bool,
         onRegenerate: @escaping () -> Void, switchNote: String? = nil, showsDetails: Bool = true,
         loadingModelName: String? = nil, statusNote: String? = nil,
         onFailureAction: @escaping (ReplyFailure.Action) -> Void = { _ in }, canAskCloud: Bool = false) {
        self.onFailureAction = onFailureAction
        self.canAskCloud = canAskCloud
        self.loadingModelName = loadingModelName
        self.statusNote = statusNote
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
                if message.fromClipboard {
                    Label("From clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("message.clipboard-badge")
                }
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

    /// Remember, Read Aloud and Copy Reply for the long-press menu of the reply text. Values only, so the closures hold no
    /// record: Remember finds the reply again in the container's main context, the one the chat reads.
    private var replyMenu: ReplyMenuActions {
        let id = message.id
        let content = message.content
        let state = app
        let container = context.container
        var remember: (@MainActor @Sendable (String) -> Void)?
        if settings.useMemory && message.thread?.memoryOff != true {
            remember = { selected in
                let context = container.mainContext
                guard let reply = try? context.fetch(FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id })).first else { return }
                try? MemoryStore(context: context).pin(selected, from: reply)
            }
        }
        return ReplyMenuActions(
            isReading: { state.speaker.speakingID == id },
            readAloud: { state.speaker.toggle(messageID: id, text: content, hub: state.voice) },
            copyReply: { UIPasteboard.general.string = content },
            remember: remember)
    }

    private var assistantRow: some View {
        // Body time of an assistant row. The MarkdownUI subtree below builds its layout later, outside this interval.
        let signpost = Perf.signposter.beginInterval("row.assistant")
        defer { Perf.signposter.endInterval("row.assistant", signpost) }
        let steps = message.toolSteps
        let parts = ReplyParts.make(
            reasoning: message.reasoning, steps: steps, content: message.content, isStreaming: isStreamingThis,
            attachments: message.attachments)
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
            // What the question saved to memory leads the reply's trace.
            ForEach(message.memoryUpdates) { update in MemoryUpdateRow(update: update, message: message) }
            // A skill the model proposed waits here for Save or Discard.
            ForEach(message.skillProposals) { proposal in SkillProposalRow(proposal: proposal, message: message) }
            ForEach(parts) { part in
                switch part {
                case .reasoning(let trace, let isStreaming): ReasoningRow(trace: trace, isStreaming: isStreaming)
                case .toolStep(let calls): ToolChainView(steps: calls, answerStarted: answerStarted)
                case .subagent(let subagent): SubagentCard(subagent: subagent)
                // Read Aloud and Copy Reply in the selection menu of the reply's text.
                case .text(let text):
                    MarkdownReply(text: text).environment(\.replyMenuActions, replyMenu)
                        .accessibilityActions {
                            if !isStreamingThis {
                                Button("Copy reply") { UIPasteboard.general.string = message.content }
                                if showsRegenerate { Button("Regenerate", action: onRegenerate) }
                            }
                        }
                case .file(let attachment), .image(let attachment):
                    MessageAttachments(attachments: [attachment], alignment: .leading)
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
                } else if let statusNote {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(statusNote).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("status-note")
                } else {
                    TypingDots()
                        .padding(.vertical, 8)
                }
            }
            if !isStreamingThis, let failure = message.failure {
                // Retry only on the last reply: it replaces that reply.
                ReplyFailureView(
                    failure: failure,
                    plan: ReplyFailureLogic.plan(
                        for: failure.kind, canRetry: showsRegenerate,
                        canAskCloud: canAskCloud && EscalationLogic.isDeviceReply(modelID: message.modelID)),
                    onAction: onFailureAction)
            }
            if let footer = ReplyFooter.make(
                content: message.content, isStreaming: isStreamingThis, showsRegenerate: showsRegenerate,
                showsDetails: showsDetails, requestedName: message.modelName, requestedID: message.modelID,
                metadata: message.metadata, steps: steps,
                reasoningMs: message.reasoning?.durationMs) {
                ReplyFooterRow(message: message, footer: footer, onRegenerate: onRegenerate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isStreamingThis) { wasStreaming, isStreaming in
            guard let text = AccessibilityLogic.replyFinishedAnnouncement(
                wasStreaming: wasStreaming, isStreaming: isStreaming, hasContent: !message.content.isEmpty,
                failed: message.failure != nil) else { return }
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// The SF Symbols "typing" animation, shown before the first token arrives. Still under Reduce Motion.
struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: !reduceMotion)
            .accessibilityLabel("Thinking")
    }
}
