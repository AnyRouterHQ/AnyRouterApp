import SwiftUI

/// A subagent as one collapsed line, "Subagent · Research · 4 steps", with a chevron. Open, it shows the model it ran on,
/// its own steps (the same rows as the tool chain) and what it answered.
struct SubagentCard: View {
    let subagent: Subagent
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                    Text(SubagentLogic.heading(subagent)).font(.footnote).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    status
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SubagentLogic.heading(subagent))
            .accessibilityValue(statusText)
            .accessibilityHint(expanded ? "Hides its steps" : "Shows its steps")
            .accessibilityIdentifier("subagent.card")
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let model = subagent.modelLabel {
                        Text("Model: \(model)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !subagent.steps.isEmpty { ToolChainView(steps: subagent.steps, answerStarted: false) }
                    if let result = subagent.result {
                        Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 26)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }

    @ViewBuilder
    private var status: some View {
        switch subagent.status {
        case .running: ProgressView().controlSize(.small)
        case .failed: Image(systemName: "exclamationmark.triangle")
        case .cancelled: Image(systemName: "xmark.circle")
        case .done: EmptyView()
        }
    }

    private var statusText: String {
        switch subagent.status {
        case .running: String(localized: "Running")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        case .done: String(localized: "Done")
        }
    }
}
