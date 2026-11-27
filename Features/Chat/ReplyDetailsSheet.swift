import SwiftUI

/// Everything stored about one reply, in a native list: model, speed, tokens and cost, the agent's tool calls, and the
/// ids for a bug report. The sections and rows come from `ReplyDetails`; "Copy all" puts them on the pasteboard as text.
struct ReplyDetailsSheet: View {
    let details: ReplyDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(details.sections.enumerated()), id: \.offset) { _, section in
                    Section(section.title) {
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                            LabeledContent(row.label) {
                                Text(row.value).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("reply.details")
            .navigationTitle("Reply details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy all") { UIPasteboard.general.string = details.copyAllText }
                        .accessibilityIdentifier("reply.details.copy-all")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
