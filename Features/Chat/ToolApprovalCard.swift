import SwiftUI

/// The approval of a tool call, inline under the call's row (decision D27): who receives it, why it asks, and the
/// same three answers as the system dialog. It answers the app's one `ToolApprovalCenter`, so the tool loop resumes
/// exactly as it does from the dialog.
struct ToolApprovalCard: View {
    let request: ToolApprovalRequest
    let answer: (ToolDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ToolApprovalPrompt.title(for: request)).font(.subheadline.weight(.semibold))
            Text(ToolApprovalPrompt.message(for: request))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            // Large controls keep the 44 pt hit area; they wrap to a column when one row does not fit (large text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool-approval.inline")
    }

    @ViewBuilder private var buttons: some View {
        Button { answer(.allowOnce) } label: { Text("Allow once").prominentLabel() }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tool-approval.inline.allow-once")
        // Same rule as the dialog: a request with a reason is about this one call.
        if request.reason == nil || request.canRemember {
            Button("Always allow") { answer(.alwaysAllow) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tool-approval.inline.always-allow")
        }
        Button("Don't allow", role: .cancel) { answer(.deny) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tool-approval.inline.deny")
    }
}
