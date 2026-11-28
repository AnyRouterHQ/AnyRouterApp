import SwiftUI

/// The tool calls of a reply, in order. While a call runs, or before the answer starts, every call is a row.
/// Once the answer has started they fold into one sentence ("Searched the web and read 3 pages") that opens to the rows.
/// A failed or denied call stays as its own row under the sentence.
struct ToolChainView: View {
    let steps: [ToolStep]
    let answerStarted: Bool
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chain = ToolChain(steps: steps, answerStarted: answerStarted)
        if chain.isCollapsed {
            // The same row as reasoning and subagents: a symbol, one line of words, a chevron. A DisclosureGroup would tint it.
            VStack(alignment: .leading, spacing: 0) {
                Button { isOpen.toggle() } label: {
                    TraceRow(symbol: "wrench.and.screwdriver", isExpanded: isOpen) {
                        Text(chain.heading).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "Hides the steps" : "Shows the steps")
                .accessibilityIdentifier("tool.chain")
                if isOpen {
                    rows(chain.rows).padding(.leading, TraceRowMetrics.contentInset)
                } else {
                    rows(chain.foldedRows).padding(.leading, TraceRowMetrics.contentInset)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: isOpen)
        } else {
            rows(chain.rows)
        }
    }

    private func rows(_ rows: [ToolChain.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if let step = steps.first(where: { $0.id == row.id }) { ToolStepRow(row: row, step: step) }
            }
        }
    }
}

/// One call: its symbol, name, a short argument summary, a status and the same chevron as the rows above it.
/// Tap for the arguments and the result. A Button, not a DisclosureGroup, which would tint the chevron with the accent.
struct ToolStepRow: View {
    let row: ToolChain.Row
    let step: ToolStep
    @State private var isOpen = false
    @Environment(AppState.self) private var app

    /// The approval the app waits for on this call, if any.
    private var approval: ToolApprovalRequest? {
        guard let request = app.toolApprovals.pending?.request, request.call.id == step.call.id else { return nil }
        return request
    }

    private var status: TraceStatus { approval == nil ? row.status : .awaitingApproval }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isOpen.toggle() } label: { label }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "Hides the arguments and result" : "Shows the arguments and result")
                .accessibilityIdentifier("tool.row")
            if let approval {
                ToolApprovalCard(request: approval) { app.toolApprovals.resolveCurrent($0) }
                    .padding(.bottom, 8)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ToolDetailText(title: "Arguments", text: ToolRowLogic.prettyJSON(step.call.argumentsJSON))
                    if let result = step.result {
                        ToolDetailText(title: "Result", text: ToolRowLogic.clipped(result.text))
                    }
                }
                .padding(.top, 4)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: isOpen)
    }

    private var label: some View {
        TraceRow(status: status, isExpanded: isOpen) {
            ToolSourceIcon(icon: row.icon)
        } title: {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(.footnote.weight(.medium))
                if let summary = row.summary {
                    Text(summary).font(.caption).lineLimit(1)
                }
            }
        }
        // One element that reads the full sentence, so VoiceOver and the UI tests get the same words as before.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.title)
        .accessibilityValue(status.accessibilityText)
    }
}

/// Arguments or a result in monospace, cut to a few lines until "Show more" is tapped.
private struct ToolDetailText: View {
    let title: String
    let text: String
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(showsAll ? nil : 6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if ToolRowLogic.exceedsPreview(text) {
                Button(showsAll ? "Show less" : "Show more") { showsAll.toggle() }
                    .font(.caption)
                    .frame(minHeight: 44)
            }
        }
    }
}
