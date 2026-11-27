import SwiftUI

/// The quiet row under a finished reply: copy, share, read aloud and regenerate, then the short model name and the
/// sources the answer drew on. The model name opens cost, speed and tokens; the sources open a list. What shows, and in
/// which order, comes from `ReplyFooter`. When the row is too wide for the screen, the model and sources drop to a
/// second line instead of scrolling out of sight.
struct ReplyFooterRow: View {
    let message: MessageRecord
    let footer: ReplyFooter
    var onRegenerate: () -> Void

    @State private var expanded = false
    @State private var showsSources = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    actions
                    info
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) { actions }
                    HStack(spacing: 0) { info }
                }
            }
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
                CopyButton(text: message.content, iconFont: .body)
            case .share:
                ShareLink(item: message.content) {
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                // The HIG minimum hit area; a borderless button is only as big as its symbol.
                .frame(minWidth: 44, minHeight: 44)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("reply.share")
            case .readAloud:
                ReadAloudButton(message: message)
            case .regenerate:
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .hoverEffect(.highlight)
                .accessibilityLabel("Regenerate")
                .accessibilityIdentifier("reply.regenerate")
            }
        }
    }

    /// The model's full name, for VoiceOver: the short label drops the size and variant.
    private var modelAccessibilityLabel: String {
        let full = ResponseFormat.title(requestedName: message.modelName, requestedID: message.modelID, metadata: message.metadata)
        return full.map { "Model, \($0)" } ?? "Details"
    }

    @ViewBuilder
    private var info: some View {
        if footer.hasDetails {
            Button { expanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text(footer.modelLabel ?? "Details")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").imageScale(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(modelAccessibilityLabel)
            .accessibilityHint(expanded ? "Hides cost, speed and tokens" : "Shows cost, speed and tokens")
            .accessibilityIdentifier("response-details")
        } else if let label = footer.modelLabel {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .accessibilityLabel(modelAccessibilityLabel)
        }
        if let sourcesLabel = footer.sourcesLabel {
            Button { showsSources = true } label: {
                HStack(spacing: 8) {
                    FaviconChain(sources: footer.faviconSources)
                    Text(sourcesLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
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
