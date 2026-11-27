import CryptoKit
import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct VoiceModelDownloaderTests {
    private let first = URL(string: "https://example.com/a/one.bin")!
    private let second = URL(string: "https://example.com/a/two.bin")!
    private let hello = Data("hello".utf8)
    private let world = Data("world!".utf8)

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func model(secondSHA: String? = nil) -> VoiceModel {
        var model = VoiceFixtures.model("whisper-test", size: 11)
        model.files = [
            VoiceModelFile(path: "enc/one.bin", url: first, sizeBytes: 5, sha256: sha(hello)),
            VoiceModelFile(path: "two.bin", url: second, sizeBytes: 6, sha256: secondSHA),
        ]
        return model
    }

    private func makeDownloader(_ served: [URL: Data]) -> (VoiceModelDownloader, FakeVoiceTransport, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString)", directoryHint: .isDirectory)
        let storage = VoiceModelStorage(root: root)
        let transport = FakeVoiceTransport(storage: storage, served)
        return (VoiceModelDownloader(storage: storage, transport: transport), transport, root)
    }

    @Test func downloadsEveryFileVerifiesAndMarksTheModelInstalled() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        #expect(downloader.state(for: model) == .notInstalled)
        let task = try #require(downloader.start(model))
        #expect(downloader.state(for: model).isActive)
        await task.value
        #expect(downloader.state(for: model) == .installed)
        #expect(downloader.isInstalled(model) && downloader.installedIDs(in: [model, .system(.stt)]) == [model.id])
        let storage = downloader.storage
        #expect(try Data(contentsOf: storage.fileURL(id: model.id, path: "enc/one.bin")) == hello)
        #expect(try Data(contentsOf: storage.fileURL(id: model.id, path: "two.bin")) == world)
        #expect(storage.manifest(model.id)?.sizeBytes == 11 && storage.installedBytes(model.id) == 11)
        #expect(!storage.isDownloading(model.id), "the marker goes with the job")
        #expect(!FileManager.default.fileExists(atPath: storage.partialFileURL(id: model.id, path: "two.bin").path), "nothing is left in the partial folder")
        #expect(transport.enqueued.sorted() == ["enc/one.bin", "two.bin"], "every file is queued at once")
    }

    @Test func aWrongChecksumFailsAndOnlyThatFileIsFetchedAgain() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: Data("WORLD!".utf8)])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        await downloader.start(model)?.value
        guard case .failed(let message) = downloader.state(for: model) else {
            Issue.record("expected a failed download, got \(downloader.state(for: model))")
            return
        }
        #expect(message.contains("two.bin"))
        #expect(!downloader.storage.isInstalled(model.id))
        #expect(!downloader.storage.isDownloading(model.id), "a failed download is not taken up again by itself")
        #expect(transport.enqueued.count == 2)
        transport.serve(second, world)
        await downloader.start(model)?.value
        #expect(downloader.state(for: model) == .installed)
        #expect(transport.enqueued.count == 3, "the file that passed is kept")
    }

    @Test func aFileOfTheWrongSizeIsRefused() async throws {
        let (downloader, _, root) = makeDownloader([first: hello, second: Data("wor".utf8)])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        await downloader.start(model)?.value
        guard case .failed(let message) = downloader.state(for: model) else {
            Issue.record("expected a failed download")
            return
        }
        #expect(message.contains("two.bin"))
    }

    @Test func aNetworkErrorFailsAndGetTriesAgain() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        transport.fails = true
        let model = model()
        await downloader.start(model)?.value
        guard case .failed = downloader.state(for: model) else {
            Issue.record("expected a failed download")
            return
        }
        await Task.yield()
        #expect(transport.cancelled == [model.id], "the other files are stopped")
        transport.fails = false
        await downloader.start(model)?.value
        #expect(downloader.state(for: model) == .installed)
    }

    @Test func cancelStopsTheDownloadAndRemovesWhatWasFetched() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        transport.hangs = true
        let model = model()
        let task = try #require(downloader.start(model))
        #expect(downloader.start(model) == nil, "a second Get while it runs does nothing")
        await Task.yield()
        var outcomes: [VoiceDownloadOutcome] = []
        downloader.onFinished = { _, outcome in outcomes.append(outcome) }
        downloader.cancel(model)
        await task.value
        #expect(downloader.state(for: model) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: downloader.storage.directory(for: model.id).path))
        #expect(outcomes == [.cancelled])
        await Task.yield()
        #expect(transport.cancelled == [model.id], "the queued files are stopped")
    }

    @Test func aCancelBeforeTheJobStartedLeavesNothingBehind() async throws {
        let (downloader, _, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let task = try #require(downloader.start(model))
        downloader.cancel(model)
        await task.value
        #expect(downloader.state(for: model) == .notInstalled)
        #expect(!downloader.storage.isDownloading(model.id), "a cancelled download is not resumed after a relaunch")
    }

    @Test func progressGrowsWithTheBytesOfEveryFileAndNeverMovesBack() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        transport.hangs = true
        let model = model()
        let task = try #require(downloader.start(model))
        await Task.yield()
        #expect(downloader.storage.isDownloading(model.id), "a relaunch knows the job")
        let one = DownloadTaskTag(voiceModelID: model.id, path: "enc/one.bin").entryID
        let two = DownloadTaskTag(voiceModelID: model.id, path: "two.bin").entryID
        transport.send(.progress(entryID: one, path: "enc/one.bin", writtenBytes: 3))
        #expect(downloader.state(for: model) == .downloading(received: 3, total: 11))
        transport.send(.progress(entryID: two, path: "two.bin", writtenBytes: 2))
        #expect(downloader.state(for: model) == .downloading(received: 5, total: 11))
        transport.send(.progress(entryID: one, path: "enc/one.bin", writtenBytes: 1))
        #expect(downloader.state(for: model) == .downloading(received: 5, total: 11), "a late smaller report changes nothing")
        transport.send(.progress(entryID: two, path: "two.bin", writtenBytes: 600))
        #expect(downloader.state(for: model) == .downloading(received: 9, total: 11), "a file counts at most its size")
        downloader.cancel(model)
        await task.value
    }

    @Test func eventsOfOtherModelsAndOfChatModelsAreIgnored() async throws {
        let (downloader, transport, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        transport.hangs = true
        let model = model()
        let task = try #require(downloader.start(model))
        await Task.yield()
        transport.send(.progress(entryID: "voice/other", path: "x", writtenBytes: 5))
        transport.send(.progress(entryID: "gguf/org/m/m.gguf", path: "x", writtenBytes: 5))
        transport.send(.fileFailed(entryID: "voice/other", path: "x", message: "no"))
        transport.send(.fileCancelled(entryID: DownloadTaskTag(voiceModelID: model.id, path: "two.bin").entryID, path: "two.bin"))
        transport.send(.backgroundEventsFinished)
        #expect(downloader.state(for: model) == .downloading(received: 0, total: 11))
        downloader.cancel(model)
        await task.value
    }

    /// The app was closed while the system kept going: one file is complete in the partial folder, the other is still running.
    @Test func restoreKeepsCompleteFilesAndDoesNotQueueRunningOnesAgain() async throws {
        let (downloader, transport, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        try downloader.storage.markDownloading(model.id)
        try transport.land(model.id, path: "enc/one.bin", hello)
        transport.live = ["two.bin"]
        downloader.restore([model, .system(.stt), VoiceFixtures.model("never-started")])
        #expect(downloader.state(for: model).isActive)
        #expect(downloader.state(for: VoiceFixtures.model("never-started")) == .notInstalled, "only a marked model is taken up")
        await Task.yield()
        #expect(transport.enqueued.isEmpty, "the file that is complete is kept and the running one stays queued once")
        try transport.land(model.id, path: "two.bin", world)
        transport.send(.fileFinished(entryID: DownloadTaskTag(voiceModelID: model.id, path: "two.bin").entryID, path: "two.bin"))
        for _ in 0..<50 where !downloader.isInstalled(model) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(downloader.state(for: model) == .installed)
        #expect(try Data(contentsOf: downloader.storage.fileURL(id: model.id, path: "two.bin")) == world)
    }

    @Test func restoreFinishesAJobWhoseFilesAllLandedWhileTheAppWasAway() async throws {
        let (downloader, transport, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        try downloader.storage.markDownloading(model.id)
        try transport.land(model.id, path: "enc/one.bin", hello)
        try transport.land(model.id, path: "two.bin", world)
        var outcomes: [VoiceDownloadOutcome] = []
        downloader.onFinished = { _, outcome in outcomes.append(outcome) }
        await downloader.start(model)?.value
        #expect(downloader.state(for: model) == .installed && outcomes == [.installed])
        #expect(transport.enqueued.isEmpty)
    }

    @Test func aCompleteFileThatFailsItsChecksumAfterARelaunchFailsTheJob() async throws {
        let (downloader, transport, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        try downloader.storage.markDownloading(model.id)
        try transport.land(model.id, path: "enc/one.bin", Data("HELLO".utf8))
        try transport.land(model.id, path: "two.bin", world)
        await downloader.start(model)?.value
        guard case .failed(let message) = downloader.state(for: model) else {
            Issue.record("expected a failed download")
            return
        }
        #expect(message.contains("one.bin"))
    }

    @Test func aModelWithNoFilesInstallsAtOnce() async throws {
        let (downloader, _, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = VoiceFixtures.model("whisper-empty")
        await downloader.start(empty)?.value
        #expect(downloader.state(for: empty) == .installed)
    }

    @Test func deleteRemovesAnInstalledModelAndCancelsARunningOne() async throws {
        let (downloader, transport, root) = makeDownloader([first: hello, second: world])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        await downloader.start(model)?.value
        try downloader.delete(model)
        #expect(downloader.state(for: model) == .notInstalled)
        #expect(!downloader.storage.isInstalled(model.id))

        transport.hangs = true
        let task = try #require(downloader.start(model))
        await Task.yield()
        try downloader.delete(model)
        await task.value
        #expect(downloader.state(for: model) == .notInstalled)
    }

    @Test func theSystemRowIsAlwaysInstalled() {
        let (downloader, _, root) = makeDownloader([:])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(downloader.state(for: .system(.tts)) == .installed)
        #expect(downloader.start(.system(.tts)) == nil)
    }
}
