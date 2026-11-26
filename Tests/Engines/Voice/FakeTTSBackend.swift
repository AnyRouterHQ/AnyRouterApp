import Foundation
@testable import AnyRouter

/// A neural voice the test drives by hand. Locked because the engine's tasks and the test both touch it.
final class FakeTTSBackend: TTSBackend, @unchecked Sendable {
    struct Call: Equatable {
        var text: String
        var language: TTSKitLanguage
    }

    private struct State {
        var calls: [Call] = []
        var holds = false
        var failure: (any Error)?
        var finished = 0
        var active = 0
        var overlapped = false
        var unloads = 0
    }

    private let lock = NSLock()
    private var state = State()

    var calls: [Call] { lock.withLock { state.calls } }
    var finished: Int { lock.withLock { state.finished } }
    var overlapped: Bool { lock.withLock { state.overlapped } }
    var unloads: Int { lock.withLock { state.unloads } }

    /// With `holds`, `speak` plays until `release` or until its task is cancelled.
    func hold() { lock.withLock { state.holds = true } }
    func release() { lock.withLock { state.holds = false } }
    func fail(_ error: any Error) { lock.withLock { state.failure = error } }

    func speak(_ text: String, language: TTSKitLanguage) async throws {
        let failure: (any Error)? = lock.withLock {
            state.calls.append(Call(text: text, language: language))
            state.active += 1
            if state.active > 1 { state.overlapped = true }
            return state.failure
        }
        defer { lock.withLock { state.active -= 1 } }
        if let failure { throw failure }
        while lock.withLock({ state.holds }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(2))
        }
        lock.withLock { state.finished += 1 }
    }

    func unload() async { lock.withLock { state.unloads += 1 } }
}
