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
                TraceRow(symbol: "person.2", status: subagent.status == .done ? nil : subagent.status, isExpanded: expanded) {
                    Text(SubagentLogic.heading(subagent)).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SubagentLogic.heading(subagent))
            .accessibilityValue(subagent.status.accessibilityText)
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
                .padding(.leading, TraceRowMetrics.contentInset)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }
}
