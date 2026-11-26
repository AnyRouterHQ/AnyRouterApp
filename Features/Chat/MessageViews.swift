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
        return VStack(alignment: .leading, spacing: 6) {
            if let switchNote {
                Text(switchNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("switch-note")
            }
            ForEach(steps) { ToolStepRow(step: $0) }
            if message.content.isEmpty && isStreamingThis && !steps.contains(where: { $0.result == nil }) {
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
            } else if !message.content.isEmpty {
                MarkdownReply(text: message.content)
            }
            if !isStreamingThis && !message.content.isEmpty {
                ReplyFooter(message: message, showsRegenerate: showsRegenerate, onRegenerate: onRegenerate,
                            showsDetails: showsDetails)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line under a reply: the actions first, then the model that wrote it with its cost and first-token time.
/// The line scrolls sideways when it does not fit. The chevron opens the rest of the details.
struct ReplyFooter: View {
    let message: MessageRecord
    let showsRegenerate: Bool
    var onRegenerate: () -> Void
    let showsDetails: Bool
    @State private var expanded = false

    private var metadata: ResponseMetadata? { message.metadata }

    private var title: String? {
        ResponseFormat.title(requestedName: message.modelName, requestedID: message.modelID, metadata: metadata)
    }

    private var brand: ModelBrand {
        (metadata?.servedModelID ?? message.modelID).map { ModelBrand.resolve(id: $0) } ?? ModelBrand.unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    CopyButton(text: message.content)
                    ReadAloudButton(message: message)
                    if showsRegenerate {
                        Button(action: onRegenerate) {
                            Label("Regenerate", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        // The HIG minimum hit area; a borderless button is only as big as its symbol.
                        .frame(minWidth: 44, minHeight: 44)
                        .hoverEffect(.highlight)
                        .accessibilityLabel("Regenerate")
                    }
                    info
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if expanded, let metadata { details(metadata) }
        }
    }

    @ViewBuilder
    private var info: some View {
        if let title {
            if showsDetails, let metadata {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        ModelLabel(name: title, brand: brand, style: .inline)
                        Text(ResponseFormat.inline(metadata).joined(separator: " · ")).lineLimit(1).fixedSize()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").imageScale(.small)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .padding(.leading, 8)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("response-details")
            } else {
                ModelLabel(name: title, brand: brand, style: .inline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
    }

    private func details(_ metadata: ResponseMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ResponseFormat.expanded(metadata), id: \.label) { field in
                HStack(alignment: .firstTextBaseline) {
                    Text(field.label)
                    Spacer(minLength: 12)
                    Text(field.value).textSelection(.enabled).multilineTextAlignment(.trailing)
                    if field.label == ResponseFormat.requestLabel { CopyButton(text: field.value) }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One tool call: a spinner or status icon and a title, expandable to the arguments and the result.
struct ToolStepRow: View {
    let step: ToolStep

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                detail("Arguments", ToolRowLogic.prettyJSON(step.call.argumentsJSON))
                if let result = step.result {
                    detail("Result", ToolRowLogic.clipped(result.text))
                }
            }
            .padding(.top, 4)
        } label: {
            Label {
                Text(ToolRowLogic.title(for: step)).lineLimit(2)
            } icon: {
                switch ToolRowLogic.status(of: step) {
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle")
                case .failed: Image(systemName: "exclamationmark.triangle")
                case .cancelled: Image(systemName: "xmark.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("tool.row")
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
