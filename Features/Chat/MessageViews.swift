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
        VStack(alignment: .leading, spacing: 6) {
            if message.content.isEmpty && isStreamingThis {
                TypingDots()
                    .padding(.vertical, 8)
            } else {
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
