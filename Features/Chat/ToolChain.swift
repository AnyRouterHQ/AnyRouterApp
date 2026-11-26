import Foundation

/// How the tool calls of one reply are shown: a compact row per call in call order, folded into one
/// "Used 3 tools" line once the answer has started and no call is still running.
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
            Row(id: step.id, icon: ToolRowLogic.icon(for: step.call.name),
                name: ToolRowLogic.displayName(for: step.call.name), summary: ToolRowLogic.summary(for: step.call),
                title: ToolRowLogic.title(for: step), status: ToolRowLogic.status(of: step))
        }
        let running = rows.contains { $0.status == .running }
        isCollapsed = answerStarted && !running && !rows.isEmpty
        heading = ToolChain.heading(count: rows.count, failed: rows.filter { $0.status == .failed }.count, running: running)
    }

    static func heading(count: Int, failed: Int, running: Bool) -> String {
        let noun = count == 1 ? "tool" : "tools"
        if running { return "Using \(count) \(noun)" }
        return failed > 0 ? "Used \(count) \(noun), \(failed) failed" : "Used \(count) \(noun)"
    }
}
