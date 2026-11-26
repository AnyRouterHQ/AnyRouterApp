import SwiftUI

/// Text of the approval prompt. Pure, so it is easy to test.
enum ToolApprovalPrompt {
    /// Longest argument text the message shows.
    static let maxArgumentCharacters = 300

    static func title(for request: ToolApprovalRequest) -> String {
        "Allow \(request.spec.title ?? request.spec.name)?"
    }

    /// The server name, then the arguments as compact JSON.
    static func message(for request: ToolApprovalRequest) -> String {
        "\(request.serverName)\n\(compactJSON(request.call.argumentsJSON))"
    }

    static func compactJSON(_ text: String, limit: Int = maxArgumentCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var compact = trimmed
        if let data = trimmed.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            let out = try? JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
            let string = String(data: out, encoding: .utf8) {
            compact = string
        }
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "…"
    }
}

extension View {
    /// Asks before a tool that is not read-only runs. Dismissing the dialog without a choice denies the call.
    func toolApprovalDialog(_ center: ToolApprovalCenter) -> some View {
        modifier(ToolApprovalDialog(center: center))
    }
}

private struct ToolApprovalDialog: ViewModifier {
    let center: ToolApprovalCenter
    /// A button just answered; the dismissal that follows in the same turn must not deny the next request in the queue.
    @State private var answered = false

    func body(content: Content) -> some View {
        content.confirmationDialog(
            center.pending.map { ToolApprovalPrompt.title(for: $0.request) } ?? "",
            isPresented: Binding(
                get: { center.pending != nil },
                set: { shown in
                    guard !shown else { return }
                    if !answered { center.resolveCurrent(.deny) }
                }),
            titleVisibility: .visible,
            presenting: center.pending
        ) { _ in
            Button("Allow once") { answer(.allowOnce) }
                .accessibilityIdentifier("tool-approval.allow-once")
            Button("Always allow") { answer(.alwaysAllow) }
                .accessibilityIdentifier("tool-approval.always-allow")
            Button("Don't allow", role: .cancel) { answer(.deny) }
                .accessibilityIdentifier("tool-approval.deny")
        } message: { entry in
            Text(ToolApprovalPrompt.message(for: entry.request))
        }
    }

    private func answer(_ decision: ToolDecision) {
        answered = true
        center.resolveCurrent(decision)
        Task { @MainActor in
            await Task.yield()
            answered = false
        }
    }
}
