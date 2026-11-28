import Foundation
import SwiftData

/// Runs from before this launch that were generating or running a tool are marked interrupted (agent design 1.3). Their
/// replies already carry the interrupted marker (unit G1), so the chat shows them with Retry, and an approved write or
/// external call with no result says it may not have finished. A run that waits for the user is left for its chat.
@MainActor
enum AgentRunSweep {
    static func run(_ context: ModelContext) {
        guard let runs = try? context.fetch(FetchDescriptor<AgentRunRecord>()) else { return }
        for run in runs {
            let status = AgentRunLogic.afterRelaunch(run.status)
            guard status != run.status else { continue }
            run.status = status
            let id = run.messageID
            let replies = try? context.fetch(FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id }))
            guard let reply = replies?.first else { continue }
            let steps = AgentRunLogic.settled(reply.toolSteps, sideEffects: run.state.sideEffects)
            if steps != reply.toolSteps { reply.toolSteps = steps }
        }
        try? context.save()
    }
}
