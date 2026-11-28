import SwiftUI
import UIKit

/// A reply that did not finish (`MessageRecord.failure`): one status symbol and one plain sentence, the one action
/// that helps, the rest behind More, and the engine's own words collapsed behind Details.
struct ReplyFailureView: View {
    let failure: ReplyFailure
    let plan: ReplyFailureLogic.ActionPlan
    let onAction: (ReplyFailure.Action) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(ReplyFailureLogic.message(for: failure.kind))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reply-failure")
            } icon: {
                Image(systemName: ReplyFailureLogic.symbol(for: failure.kind)).foregroundStyle(.secondary)
            }
            actions.padding(.leading, TraceRowMetrics.contentInset)
            DisclosureGroup("Details") {
                detail.padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, TraceRowMetrics.contentInset)
        }
    }

    /// Side by side while they fit on one line each; stacked and full width at accessibility text sizes.
    private var actions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        let stacked = typeSize.isAccessibilitySize
        return layout {
            if let primary = plan.primary {
                Button(ReplyFailureLogic.title(of: primary)) { onAction(primary) }
                    .buttonStyle(.borderedProminent)
                    .lineLimit(stacked ? nil : 1)
                    .fixedSize(horizontal: !stacked, vertical: true)
                    .frame(maxWidth: stacked ? .infinity : nil)
                    .accessibilityIdentifier("reply-failure.\(primary)")
            }
            Menu {
                ForEach(plan.more, id: \.self) { action in
                    Button(ReplyFailureLogic.title(of: action)) { onAction(action) }
                        .accessibilityIdentifier("reply-failure.\(action)")
                }
                Button("Copy details", systemImage: "doc.on.doc") { UIPasteboard.general.string = failure.detail }
                    .accessibilityIdentifier("reply-failure.menu.copy")
            } label: {
                Text("More").lineLimit(1).frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: !stacked, vertical: true)
            .accessibilityIdentifier("reply-failure.more")
        }
        .controlSize(.regular)
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
