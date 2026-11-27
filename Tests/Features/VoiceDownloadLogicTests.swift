import Foundation
import Testing
@testable import AnyRouter

/// The states the voice button and the banner draw: idle, downloading with progress, paused or failed with a retry, done.
struct VoiceDownloadLogicTests {
    private let tiny = VoiceFixtures.model("whisper-tiny", order: 1)
    private let small = VoiceFixtures.model("whisper-small", order: 3)

    private func state(
        target: String? = "whisper-tiny", finished: String? = nil, _ download: ModelDownloadState
    ) -> VoiceDownloadState {
        VoiceDownloadLogic.state(target: target, finished: finished, models: [tiny, small], download: { _ in download })
    }

    @Test func nothingChosenOrAnUnknownModelIsIdle() {
        #expect(state(target: nil, .downloading(received: 1, total: 2)) == .idle)
        #expect(state(target: "gone", .downloading(received: 1, total: 2)) == .idle)
        #expect(state(.notInstalled) == .idle)
        #expect(!VoiceDownloadState.idle.showsProgress && !VoiceDownloadState.idle.canRetry)
    }

    @Test func downloadingCarriesTheFractionForTheRing() {
        let s = state(.downloading(received: 25, total: 100))
        #expect(s.phase == .downloading && s.fraction == 0.25 && s.showsProgress && !s.canRetry)
        #expect(s.modelID == "whisper-tiny" && s.title == "whisper-tiny")
    }

    @Test func verifyingIsAnIndeterminateRingAndPausedOffersRetry() {
        let verifying = state(.verifying)
        #expect(verifying.phase == .verifying && verifying.fraction == nil && verifying.showsProgress && !verifying.canRetry)
        let paused = state(.paused(received: 50, total: 100))
        #expect(paused.phase == .paused && paused.fraction == 0.5 && paused.showsProgress && paused.canRetry)
    }

    @Test func aFailureKeepsItsMessageAndOffersRetry() {
        let s = state(.failed("No connection"))
        #expect(s.phase == .failed && s.message == "No connection" && s.canRetry && !s.showsProgress)
    }

    @Test func installedIsReadyOnlyForTheModelThatJustFinished() {
        let ready = state(target: nil, finished: "whisper-small", .installed)
        #expect(ready.phase == .ready && ready.modelID == "whisper-small" && !ready.showsProgress && !ready.canRetry)
        #expect(state(target: "whisper-tiny", finished: "whisper-small", .installed) == .idle, "the chosen one is not installed yet")
    }
}
