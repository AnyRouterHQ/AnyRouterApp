import SwiftUI

/// The quiet row under a finished reply: copy and regenerate, then one line of text ("Haiku 4.5 · $0.0012 · 42 tok/s"),
/// then the sources the answer drew on. The line opens a sheet with every detail; the sources open a list. Read aloud and
/// share live in the reply's long-press menu. What shows, and in which order, comes from `ReplyFooter`. The row stays one
/// line and scrolls sideways when it is wider than the screen.
struct ReplyFooterRow: View {
    let message: MessageRecord
    let footer: ReplyFooter
    var onRegenerate: () -> Void

    @State private var showsSources = false
    @State private var showsDetails = false
    @State private var showsMemories = false

    var body: some View {
        // One row. When it is wider than the screen it scrolls sideways; it never wraps.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -4) {
                actions
                summary
                sourcesButton
                memoriesButton
            }
            .imageScale(.medium)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .sheet(isPresented: $showsSources) { SourcesSheet(sources: footer.sources) }
        .sheet(isPresented: $showsMemories) { MemoriesUsedSheet(hits: message.memoryHits) }
        .sheet(isPresented: $showsDetails) {
            if let details = footer.details { ReplyDetailsSheet(details: details) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        ForEach(footer.actions, id: \.self) { action in
            switch action {
            case .copy:
                // The whole reply; a long press on the reply selects any part of it in place.
                CopyButton(text: message.content, iconFont: .body)
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

    @ViewBuilder
    private var summary: some View {
        if footer.hasDetails {
            Button { showsDetails = true } label: {
                Text(footer.summary.line ?? "Details")
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
            .accessibilityHint("Shows all the details of this reply")
            .accessibilityIdentifier("response-details")
        } else if let line = footer.summary.line {
            Text(line)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
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

    /// "Used 2 memories": what recall put in front of the question, each with Forget.
    @ViewBuilder
    private var memoriesButton: some View {
        let hits = message.memoryHits
        if !hits.isEmpty {
            Button { showsMemories = true } label: {
                Label(MemoryRecallLogic.usedLabel(hits.count), systemImage: "brain")
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
            .accessibilityHint("Shows the memories this reply used")
            .accessibilityIdentifier("reply.memories")
        }
    }
}
