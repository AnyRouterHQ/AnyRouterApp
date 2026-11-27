import Foundation
import Testing
@testable import AnyRouter

/// The record a phone keeps of a local model load. When the system ends the app mid-load there is no callback, so the
/// record must already say how far it got and read as cut short.
struct ModelLoadTraceTests {
    private func stage(_ step: ModelLoadTrace.Step, _ seconds: Double, note: String? = nil) -> ModelLoadTrace.Stage {
        ModelLoadTrace.Stage(
            step: step, seconds: seconds, footprintBytes: 400_000_000, availableBytes: 2_900_000_000, note: note)
    }

    @Test func anAttemptThatStopsMidwayReadsAsCutShort() {
        let trace = ModelLoadTrace(model: "m.gguf", stages: [
            stage(.started, 0), stage(.mapped, 12.34, note: "streamed from storage, CPU only, 4096-token context"),
        ])
        #expect(trace.summary == "m.gguf · started 0.0 s · mapped 12.3 s (streamed from storage, CPU only, 4096-token context)."
            + " App memory 0.40 GB, 2.90 GB left. Ended after mapped: the system may have closed the app.")
    }

    @Test func finishedStoppedAndFailedAttemptsAreComplete() {
        for last in [ModelLoadTrace.Step.finished, .stopped, .failed] {
            let trace = ModelLoadTrace(model: "m.gguf", stages: [stage(.started, 0), stage(last, 3)])
            #expect(!trace.summary.contains("may have closed"), "\(last) is a last step")
        }
        let done = ModelLoadTrace(model: "m.gguf", stages: [stage(.firstToken, 140), stage(.finished, 300, note: "38 tokens, 0.30 tokens/s")])
        #expect(done.summary.contains("finished 300.0 s (38 tokens, 0.30 tokens/s)"))
        #expect(ModelLoadTrace(model: "m.gguf").summary == "m.gguf", "no steps yet: just the model")
    }

    @Test func everyStepHasATitle() {
        let steps: [ModelLoadTrace.Step] = [.started, .mapped, .contextReady, .firstToken, .finished, .stopped, .failed]
        #expect(steps.map(\.title) == ["started", "mapped", "context ready", "first token", "finished", "stopped", "failed"])
    }

    @Test func oneAttemptStaysOneRecordAsItsStepsAreSaved() throws {
        let store = DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"))
        var trace = ModelLoadTrace(model: "m.gguf", stages: [stage(.started, 0)])
        let name = try store.saveModelLoad(trace, now: Date(timeIntervalSince1970: 1_800_000_000))
        trace.stages.append(stage(.mapped, 5))
        #expect(try store.saveModelLoad(trace, replacing: name) == name)
        let records = store.list()
        #expect(records.map(\.kind) == [.modelLoad])
        #expect(store.modelLoadTrace(of: records[0]) == trace, "the record holds the latest steps")
    }

    @Test func onlyModelLoadRecordsThatReadGiveATrace() throws {
        let store = DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"))
        try store.saveMetrics(Data("{}".utf8), now: Date(timeIntervalSince1970: 1_800_000_000))
        try store.saveModelLoad(ModelLoadTrace(model: "m.gguf"), now: Date(timeIntervalSince1970: 1_800_000_060))
        let records = store.list()
        #expect(records.map(\.kind) == [.modelLoad, .metric])
        #expect(store.modelLoadTrace(of: records[1]) == nil)
        try Data("not json".utf8).write(to: records[0].url)
        #expect(store.modelLoadTrace(of: records[0]) == nil)
        try FileManager.default.removeItem(at: records[0].url)
        #expect(store.modelLoadTrace(of: records[0]) == nil, "a file that is gone gives no trace")
    }
}
