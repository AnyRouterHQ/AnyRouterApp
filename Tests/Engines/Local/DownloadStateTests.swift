import Foundation
import Testing
@testable import AnyRouter

struct ModelDownloadStateTests {
    private typealias S = ModelDownloadState

    @Test func happyPathGoesFromNotInstalledToInstalled() {
        var state = S.notInstalled
        state = state.reduce(.start(total: 100))
        #expect(state == .downloading(received: 0, total: 100))
        state = state.reduce(.progress(received: 40, total: 100))
        #expect(state == .downloading(received: 40, total: 100))
        state = state.reduce(.downloaded)
        #expect(state == .verifying)
        state = state.reduce(.verified)
        #expect(state == .installed)
    }

    /// The success tap: only the step into installed counts, not a refresh of a model that was already there.
    @Test func onlyTheStepIntoInstalledFinishesADownload() {
        #expect(S.verifying.finishes(into: .installed))
        #expect(!S.installed.finishes(into: .installed))
        #expect(!S.verifying.finishes(into: .failed("bad")))
        #expect(!S.notInstalled.finishes(into: .downloading(received: 0, total: 1)))
    }

    @Test func pauseKeepsProgressAndResumeContinuesFromIt() {
        var state = S.downloading(received: 40, total: 100)
        state = state.reduce(.pause)
        #expect(state == .paused(received: 40, total: 100))
        state = state.reduce(.resume)
        #expect(state == .downloading(received: 40, total: 100))
    }

    @Test func lateProgressAfterAPauseCannotReviveTheDownload() {
        let paused = S.paused(received: 40, total: 100)
        #expect(paused.reduce(.progress(received: 90, total: 100)) == paused)
    }

    @Test func lateProgressAfterCancelOrInstallIsIgnored() {
        #expect(S.notInstalled.reduce(.progress(received: 5, total: 10)) == .notInstalled)
        #expect(S.installed.reduce(.progress(received: 5, total: 10)) == .installed)
    }

    @Test func failureKeepsTheMessageAndAllowsARetry() {
        for active in [S.downloading(received: 1, total: 2), .paused(received: 1, total: 2), .verifying] {
            #expect(active.reduce(.fail("disk full")) == .failed("disk full"))
        }
        #expect(S.failed("x").reduce(.start(total: 10)) == .downloading(received: 0, total: 10))
    }

    @Test func cancelDropsAnyActiveStateButNotAnInstalledModel() {
        for active in [S.downloading(received: 1, total: 2), .paused(received: 1, total: 2), .verifying] {
            #expect(active.reduce(.cancel) == .notInstalled)
        }
        #expect(S.installed.reduce(.cancel) == .installed)
    }

    @Test func deleteOnlyAppliesToInstalledOrFailedModels() {
        #expect(S.installed.reduce(.delete) == .notInstalled)
        #expect(S.failed("x").reduce(.delete) == .notInstalled)
        #expect(S.downloading(received: 1, total: 2).reduce(.delete) == .downloading(received: 1, total: 2))
    }

    @Test func aCompletedModelCannotBeStartedAgain() {
        #expect(S.installed.reduce(.start(total: 5)) == .installed)
    }

    @Test func fractionIsOnlyKnownWhileDownloadingWithATotal() {
        #expect(S.downloading(received: 25, total: 100).fraction == 0.25)
        #expect(S.paused(received: 50, total: 100).fraction == 0.5)
        #expect(S.downloading(received: 5, total: 0).fraction == nil)
        #expect(S.downloading(received: 500, total: 100).fraction == 1)
        #expect(S.installed.fraction == nil)
    }

    @Test func activeMeansDownloadingPausedOrVerifying() {
        #expect(S.downloading(received: 0, total: 1).isActive)
        #expect(S.paused(received: 0, total: 1).isActive)
        #expect(S.verifying.isActive)
        #expect(!S.installed.isActive && !S.notInstalled.isActive && !S.failed("x").isActive)
    }
}

struct DownloadProgressTrackerTests {
    private let files = [
        HFFile(path: "a.safetensors", size: 100),
        HFFile(path: "config.json", size: 10),
    ]

    @Test func addsUpBytesAcrossFiles() {
        var tracker = DownloadProgressTracker(files: files)
        #expect(tracker.totalBytes == 110)
        tracker.update(path: "a.safetensors", receivedBytes: 30)
        tracker.update(path: "config.json", receivedBytes: 10)
        #expect(tracker.receivedBytes == 40)
    }

    @Test func duplicatePathsInAListingDoNotCrashAndCountOnce() {
        let tracker = DownloadProgressTracker(files: files + [HFFile(path: "config.json", size: 10)])
        #expect(tracker.totalBytes == 110)
        #expect(tracker.remainingPaths == ["a.safetensors", "config.json"])
    }

    @Test func neverCountsMoreThanAFileSizeAndNeverGoesBackwards() {
        var tracker = DownloadProgressTracker(files: files)
        tracker.update(path: "a.safetensors", receivedBytes: 500)
        #expect(tracker.receivedBytes == 100)
        tracker.update(path: "a.safetensors", receivedBytes: 20)
        #expect(tracker.receivedBytes == 100)
    }

    @Test func finishedFilesCountInFullAndCompleteWhenAllFinish() {
        var tracker = DownloadProgressTracker(files: files)
        tracker.markFinished(path: "config.json")
        #expect(tracker.receivedBytes == 10)
        #expect(!tracker.isComplete)
        #expect(tracker.remainingPaths == ["a.safetensors"])
        tracker.markFinished(path: "a.safetensors")
        #expect(tracker.isComplete)
        #expect(tracker.receivedBytes == 110)
        #expect(tracker.remainingPaths.isEmpty)
    }

    @Test func ignoresFilesThatAreNotPartOfTheJob() {
        var tracker = DownloadProgressTracker(files: files)
        tracker.update(path: "other.bin", receivedBytes: 99)
        tracker.markFinished(path: "other.bin")
        #expect(tracker.receivedBytes == 0)
        #expect(!tracker.isComplete)
    }

    @Test func resetForgetsAFinishedFileSoItIsFetchedAgain() {
        var tracker = DownloadProgressTracker(files: files)
        tracker.markFinished(path: "config.json")
        tracker.reset(path: "config.json")
        #expect(tracker.remainingPaths == ["a.safetensors", "config.json"])
    }

    @Test func taskTagsSurviveTheTaskDescriptionRoundTrip() {
        let tag = DownloadTaskTag(entryID: "gguf/org/m/m-Q4_K_M.gguf", path: "sub dir/m.gguf")
        #expect(DownloadTaskTag(encoded: tag.encoded) == tag)
        #expect(DownloadTaskTag(encoded: "no-separator") == nil)
    }
}
