import SwiftUI

/// Asks before a tool that is not read-only runs. Swiping the sheet away counts as Deny.
struct ToolApprovalSheet: View {
    let entry: ToolApprovalQueue.Entry
    var onDecide: (ToolDecision) -> Void

    private var request: ToolApprovalRequest { entry.request }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    LabeledContent("Server", value: request.serverName)
                    LabeledContent("Tool", value: request.spec.title ?? request.spec.name)
                }
                Section("Arguments") {
                    Text(ToolRowLogic.prettyJSON(request.call.argumentsJSON))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Allow this tool?")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { onDecide(.allowOnce) } label: { Text("Allow once").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("tool-approval.allow-once")
                    Button { onDecide(.alwaysAllow) } label: { Text("Always allow").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("tool-approval.always-allow")
                    Button(role: .destructive) { onDecide(.deny) } label: { Text("Deny").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("tool-approval.deny")
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Approval") {
    ToolApprovalSheet(
        entry: .init(id: UUID(), request: ToolApprovalRequest(
            serverName: "Example",
            spec: ToolSpec(name: "send_note", title: "Send a note", description: "", inputSchemaJSON: "{}", isReadOnly: false),
            call: ToolCall(id: "1", name: "send_note", argumentsJSON: #"{"to":"team","text":"Hello"}"#))),
        onDecide: { _ in })
}
