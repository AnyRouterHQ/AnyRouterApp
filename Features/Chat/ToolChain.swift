import Foundation

/// How the tool calls of one reply are shown: a compact row per call in call order, folded into
/// one line ("Searched the web and read 3 pages") once the answer has started and no call is still running.
struct ToolChain: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let icon: ToolSource.Icon
        let name: String
        let summary: String?
        /// The full sentence ("Searched the web for “swift 7”"), read by VoiceOver.
        let title: String
        let status: ToolRowLogic.Status
    }

    let rows: [Row]
    let isCollapsed: Bool
    let heading: String

    init(steps: [ToolStep], answerStarted: Bool) {
        rows = steps.map { step in
            Row(id: step.id, icon: ToolRowLogic.icon(for: step.call.name, sourceID: step.sourceID),
                name: ToolRowLogic.displayName(for: step.call.name), summary: ToolRowLogic.summary(for: step.call),
                title: ToolRowLogic.title(for: step), status: ToolRowLogic.status(of: step))
        }
        let running = rows.contains { $0.status == .running }
        isCollapsed = answerStarted && !running && !rows.isEmpty
        heading = ToolChain.heading(steps: steps, failed: rows.filter { $0.status == .failed }.count, running: running)
    }

    /// "Using 2 tools" while a call runs; after that what the calls did, with the failures counted at the end.
    static func heading(steps: [ToolStep], failed: Int, running: Bool) -> String {
        if running { return steps.count == 1 ? String(localized: "Using 1 tool") : String(localized: "Using \(steps.count) tools") }
        let summary = ToolSummary.text(for: steps)
        return failed > 0 ? String(localized: "\(summary) (\(failed) failed)") : summary
    }
}
