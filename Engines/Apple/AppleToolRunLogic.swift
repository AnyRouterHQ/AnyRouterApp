import Foundation

/// Runs the calls the on-device model makes through the `ToolHost` and reports them as stream deltas.
/// One scope per `stream` call: cancelling it stops every call still running.
final class ToolRunScope: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [String: Task<ToolResult, Never>] = [:]
    private var finished = 0
    private var cancelled = false

    /// Calls that have completed, so the stream loop can tell that a tool ran between two snapshots.
    var finishedCalls: Int { lock.withLock { finished } }

    func cancelAll() {
        let tasks = lock.withLock { () -> [Task<ToolResult, Never>] in
            cancelled = true
            return Array(running.values)
        }
        for task in tasks { task.cancel() }
    }

    /// Emits `.toolCall`, runs the host, emits `.toolResult`, and returns the text for the model.
    func run(
        name: String,
        argumentsJSON: String,
        host: any ToolHost,
        emit: @Sendable (ChatDelta) -> Void,
        makeID: @Sendable () -> String = { UUID().uuidString }
    ) async -> String {
        let call = ToolCall(id: makeID(), name: name, argumentsJSON: argumentsJSON)
        emit(.toolCall(call))
        let result = await execute(call, on: host)
        emit(.toolResult(result))
        lock.withLock { finished += 1 }
        return Self.modelText(for: result)
    }

    private func execute(_ call: ToolCall, on host: any ToolHost) async -> ToolResult {
        let task = Task { await host.execute(call) }
        let accepted = lock.withLock { () -> Bool in
            if cancelled { return false }
            running[call.id] = task
            return true
        }
        // After cancelAll the host still runs, but it sees a cancelled task and answers with an error result.
        if !accepted { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        lock.withLock { running[call.id] = nil }
        return result
    }

    /// The host has already cut the result to the model's `ToolProfile`; an error is marked as one.
    static func modelText(for result: ToolResult) -> String {
        result.isError ? "Error: " + result.text : result.text
    }
}
