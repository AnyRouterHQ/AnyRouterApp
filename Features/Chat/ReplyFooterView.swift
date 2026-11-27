import SwiftUI

/// The quiet row under a finished reply: copy, share, read aloud and regenerate, then the sources the answer drew on,
/// then the short model name. The model name opens cost, speed and tokens; the sources open a list. What shows, and in
/// which order, comes from `ReplyFooter`. The row stays one line and scrolls sideways when it is wider than the screen.
struct ReplyFooterRow: View {
    let message: MessageRecord
    let footer: ReplyFooter
    var onRegenerate: () -> Void

    @State private var expanded = false
    @State private var showsSources = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // One row. When it is wider than the screen it scrolls sideways; it never wraps.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -4) {
                    actions
                    sourcesButton
                    if footer.separatesSourcesAndModel {
                        Text("·").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 2).accessibilityHidden(true)
                    }
                    modelInfo
                }
                .imageScale(.medium)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if expanded, let metadata = message.metadata {
                details(metadata).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
        .sheet(isPresented: $showsSources) { SourcesSheet(sources: footer.sources) }
    }

    @ViewBuilder
    private var actions: some View {
        ForEach(footer.actions, id: \.self) { action in
            switch action {
            case .copy:
                // The whole reply; a long press on the reply selects any part of it in place.
                CopyButton(text: message.content, iconFont: .body)
            case .share:
                ShareLink(item: message.content) {
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                        // The HIG minimum hit area, inside the label so the button itself is 44 pt.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("reply.share")
            case .readAloud:
                ReadAloudButton(message: message)
            case .regenerate:
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .hoverEffect(.highlight)
                .accessibilityLabel("Regenerate")
                .accessibilityIdentifier("reply.regenerate")
            }
        }
    }

    /// The model's full name, for VoiceOver: the short label drops the size and variant.
    private var modelAccessibilityLabel: String {
        let full = ResponseFormat.title(requestedName: message.modelName, requestedID: message.modelID, metadata: message.metadata)
        guard let full else { return "Details" }
        guard let ttft = footer.ttft else { return "Model, \(full)" }
        return "Model, \(full), first word after \(ttft)"
    }

    @ViewBuilder
    private var modelInfo: some View {
        if footer.hasDetails {
            Button { expanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text(footer.modelLine ?? "Details")
                    // The same chevron as every other row in a reply.
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(modelAccessibilityLabel)
            .accessibilityHint(expanded ? "Hides cost, speed and tokens" : "Shows cost, speed and tokens")
            .accessibilityIdentifier("response-details")
        } else if let line = footer.modelLine {
            Text(line)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .accessibilityLabel(modelAccessibilityLabel)
        }
    }

    @ViewBuilder
    private var sourcesButton: some View {
        if let sourcesLabel = footer.sourcesLabel {
            Button { showsSources = true } label: {
                HStack(spacing: 6) {
                    FaviconChain(sources: footer.faviconSources)
                    Text(sourcesLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(sourcesLabel)
            .accessibilityHint("Shows the sources")
            .accessibilityIdentifier("reply.sources")
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
        .padding(.horizontal, 8)
    }
}
