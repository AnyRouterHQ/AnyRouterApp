import Foundation

/// A tool that runs on the device. Built-in tools only read: they never need the user's approval.
protocol BuiltInTool: Sendable {
    /// The name the model calls it by. Letters, digits and `_`.
    var name: String { get }
    /// Label in Settings.
    var title: String { get }
    var summary: String { get }
    /// For the model.
    var description: String { get }
    var inputSchemaJSON: String { get }
    func run(_ arguments: JSONValue) async throws -> String
}

extension BuiltInTool {
    var spec: ToolSpec {
        ToolSpec(name: name, title: title, description: description, inputSchemaJSON: inputSchemaJSON, isReadOnly: true)
    }
}

/// A failure the model should read and may recover from ("division by zero"). It ends up in a `ToolResult` with `isError`.
struct BuiltInToolError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Cuts text to `limit` characters and says so, so one answer cannot fill a small context window.
func clippedText(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "\n[Cut at \(limit) characters.]"
}

/// A call that took too long.
struct DeadlineError: LocalizedError, Equatable {
    let seconds: Double
    var errorDescription: String? { "The tool took longer than \(String(format: "%g", seconds)) seconds and was stopped." }
}

/// Runs `operation` and gives up after `seconds`, cancelling it. The operation must honor cancellation.
func withDeadline<T: Sendable>(
    _ seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DeadlineError(seconds: seconds)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        return first
    }
}
