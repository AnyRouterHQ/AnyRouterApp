import Foundation
@testable import AnyRouter

/// A Whisper model the test drives by setting what it hears and what it says. Locked because the engine's runner task
/// and the test both touch it; a real backend is never shared like this.
final class FakeWhisperBackend: WhisperBackend, @unchecked Sendable {
    private struct State {
        var seconds: Float = 3
        var isLoud = true
        var detected = "vi"
        var segments: [WhisperSegment] = []
        var startError: (any Error)?
        var transcribeError: (any Error)?
        var detectCalls = 0
        var transcribeCalls: [(language: String, from: Float)] = []
        var startCount = 0
        var stopCount = 0
        var unloadCount = 0
        var reads = 0
    }

    private let lock = NSLock()
    private var state = State()

    private func read<T>(_ body: (State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(state)
    }

    private func write(_ body: (inout State) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&state)
    }

    // Script
    func hear(seconds: Float, loud: Bool = true) { write { $0.seconds = seconds; $0.isLoud = loud } }
    func say(_ segments: [WhisperSegment], language: String = "vi") { write { $0.segments = segments; $0.detected = language } }
    func failStart(_ error: any Error) { write { $0.startError = error } }
    func failTranscribe(_ error: any Error) { write { $0.transcribeError = error } }

    // Record
    var detectCalls: Int { read(\.detectCalls) }
    var transcribeCalls: [(language: String, from: Float)] { read(\.transcribeCalls) }
    var startCount: Int { read(\.startCount) }
    var stopCount: Int { read(\.stopCount) }
    var unloadCount: Int { read(\.unloadCount) }
    var reads: Int { read(\.reads) }

    // WhisperBackend
    func startRecording() throws {
        if let error = read({ $0.startError }) { throw error }
        write { $0.startCount += 1 }
    }

    var sampleCount: Int {
        write { $0.reads += 1 }
        return Int(read(\.seconds) * WhisperVoice.sampleRate)
    }

    var energy: [Float] {
        let snapshot = read { $0 }
        return [Float](repeating: snapshot.isLoud ? 0.9 : 0, count: Int(snapshot.seconds * 10))
    }

    func samples() -> [Float] { [Float](repeating: 0, count: Int(read(\.seconds) * WhisperVoice.sampleRate)) }

    func stopRecording() { write { $0.stopCount += 1 } }

    func detectLanguage(in samples: [Float]) async throws -> String {
        write { $0.detectCalls += 1 }
        return read(\.detected)
    }

    func transcribe(_ samples: [Float], language: String, from seconds: Float) async throws -> [WhisperSegment] {
        write { $0.transcribeCalls.append((language, seconds)) }
        if let error = read({ $0.transcribeError }) { throw error }
        return read(\.segments)
    }

    func unload() async { write { $0.unloadCount += 1 } }
}
