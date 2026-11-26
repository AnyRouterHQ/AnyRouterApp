import MarkdownUI
import SwiftUI

/// One message row: user text in a rounded bubble, assistant reply as plain markdown with actions.
struct MessageRow: View {
    let message: MessageRecord
    let isStreamingThis: Bool
    let showsRegenerate: Bool
    var onRegenerate: () -> Void

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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
