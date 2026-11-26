import MarkdownUI
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

    init(message: MessageRecord, isStreamingThis: Bool, showsRegenerate: Bool,
         onRegenerate: @escaping () -> Void, switchNote: String? = nil, showsDetails: Bool = true) {
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
            Text(message.content)
                .font(.arBase)
                .foregroundStyle(ARColor.foreground)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(ARColor.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var assistantRow: some View {
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
                TypingDots()
                    .padding(.vertical, 8)
            } else if !message.content.isEmpty {
                Markdown(message.content)
                    .markdownTheme(.anyRouter)
                    .textSelection(.enabled)
            }
            if !isStreamingThis && !message.content.isEmpty {
                HStack(spacing: 4) {
                    CopyButton(text: message.content)
                    if showsRegenerate {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ARColor.mutedForeground)
                                .frame(minWidth: 28, minHeight: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Regenerate")
                    }
                }
                ResponseFooter(message: message, showsDetails: showsDetails)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Under a reply: the model that wrote it (with its logo), then cost and speed. Tap for the details.
struct ResponseFooter: View {
    let message: MessageRecord
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
        if let title {
            VStack(alignment: .leading, spacing: 6) {
                if showsDetails, let metadata {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 6) {
                            ModelLabel(name: title, brand: brand, style: .inline)
                            Text(ResponseFormat.summary(metadata).joined(separator: " · ")).lineLimit(1)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").imageScale(.small)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("response-details")
                    if expanded { details(metadata) }
                } else {
                    ModelLabel(name: title, brand: brand, style: .inline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func details(_ metadata: ResponseMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Model", metadata.servedModelID)
            row("Provider", metadata.provider)
            row("Cost", metadata.costUSD.map(PriceFormat.cost))
            row("First token", metadata.ttftMs.map(ResponseFormat.seconds))
            row("Total", metadata.totalMs.map(ResponseFormat.seconds))
            row("Speed", metadata.tokensPerSecond.map(ResponseFormat.speed))
            row("Tokens", ResponseFormat.tokens(prompt: metadata.promptTokens, completion: metadata.completionTokens))
            row("Cached tokens", metadata.cachedTokens.map(String.init))
            row("Upstream latency", metadata.upstreamLatencyMs.map(ResponseFormat.seconds))
            if let id = metadata.requestID {
                HStack(spacing: 4) {
                    row("Request", id)
                    CopyButton(text: id)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer(minLength: 12)
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        }
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
            HStack(spacing: 8) {
                switch ToolRowLogic.status(of: step) {
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle")
                case .failed: Image(systemName: "exclamationmark.triangle")
                case .cancelled: Image(systemName: "xmark.circle")
                }
                Text(ToolRowLogic.title(for: step)).lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("tool-step.\(step.call.id)")
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

/// Three pulsing dots shown before the first token arrives.
struct TypingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ARColor.mutedForeground)
                    .frame(width: 7, height: 7)
                    .opacity(phase ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: phase)
            }
        }
        .onAppear { phase = true }
        .accessibilityLabel("Thinking")
    }
}
