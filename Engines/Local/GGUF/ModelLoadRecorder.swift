import Foundation
import Synchronization

/// Saves a `ModelLoadTrace` to Diagnostics as a load goes on: one record per attempt, rewritten at each step, with the
/// app's memory at that step. Covers the load and the first reply after it.
final class ModelLoadRecorder: Sendable {
    private struct State {
        var trace: ModelLoadTrace
        var fileName: String?
    }

    private let store: DiagnosticsStore
    private let start = ContinuousClock.now
    private let state: Mutex<State>

    /// `model` is a model id or path; only its last component (the file name) is kept.
    init(store: DiagnosticsStore, model: String) {
        self.store = store
        state = Mutex(State(trace: ModelLoadTrace(model: (model as NSString).lastPathComponent)))
    }

    /// True once a load began under this recorder: the weights were not loaded yet.
    var hasStarted: Bool { state.withLock { !$0.trace.stages.isEmpty } }

    /// Started, and not finished, stopped or failed yet.
    var isOpen: Bool {
        state.withLock { state in
            guard let last = state.trace.stages.last?.step else { return false }
            return ![.finished, .stopped, .failed].contains(last)
        }
    }

    /// `mark` as a value, for the generation loop.
    var onStep: (ModelLoadTrace.Step, String?) -> Void {
        { [self] step, note in mark(step, note: note) }
    }

    func mark(_ step: ModelLoadTrace.Step, note: String? = nil) {
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let stage = ModelLoadTrace.Stage(
            step: step, seconds: seconds, footprintBytes: MemoryReading.footprintBytes(),
            availableBytes: MemoryReading.availableBytes(), note: note)
        state.withLock { state in
            state.trace.stages.append(stage)
            // Diagnostics are best effort: a full disk must not stop a chat.
            state.fileName = (try? store.saveModelLoad(state.trace, replacing: state.fileName)) ?? state.fileName
        }
    }
}
