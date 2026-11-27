import SwiftUI
import UIKit

/// A reply that did not finish (`MessageRecord.failure`): one plain sentence on a trace row with the failed status,
/// the raw text behind it with Copy, and the action that helps.
struct ReplyFailureView: View {
    let failure: ReplyFailure
    let actions: [ReplyFailure.Action]
    let onAction: (ReplyFailure.Action) -> Void
    @State private var showsDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showsDetail.toggle() } label: {
                TraceRow(symbol: ReplyFailureLogic.symbol(for: failure.kind), status: .failed, isExpanded: showsDetail) {
                    // Primary body text: the audit reads small secondary text as low contrast, and this is the answer now.
                    Text(ReplyFailureLogic.message(for: failure.kind))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsDetail ? "Hides the details" : "Shows the details")
            .accessibilityIdentifier("reply-failure")
            if showsDetail { detail.padding(.leading, TraceRowMetrics.contentInset) }
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        Button(ReplyFailureLogic.title(of: action)) { onAction(action) }
                            .accessibilityIdentifier("reply-failure.\(action)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.leading, TraceRowMetrics.contentInset)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsDetail)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.detail)
                .font(.footnote.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reply-failure.detail")
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = failure.detail }
                .font(.footnote)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityLabel("Copy details")
                .accessibilityIdentifier("reply-failure.copy")
        }
    }
}
