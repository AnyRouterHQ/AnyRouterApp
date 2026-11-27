import Foundation
import SwiftData

/// Unfinished runs from before this launch are marked interrupted (agent design 1.3). Their replies already carry the
/// interrupted marker (unit G1), so the chat shows them with Retry.
@MainActor
enum AgentRunSweep {
    static func run(_ context: ModelContext) {
        guard let runs = try? context.fetch(FetchDescriptor<AgentRunRecord>()) else { return }
        for run in runs {
            let status = AgentRunLogic.afterRelaunch(run.status)
            if status != run.status { run.status = status }
        }
        try? context.save()
    }
}
