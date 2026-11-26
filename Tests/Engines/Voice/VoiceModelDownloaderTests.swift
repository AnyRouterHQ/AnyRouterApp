import CryptoKit
import Foundation
import Testing
@testable import AnyRouter

/// Serves bytes from a dictionary and counts the fetches.
private final class FakeFetcher: VoiceFileFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [URL: Data]
    private var counted = 0
    var fails = false
    var hangs = false

    init(_ bytes: [URL: Data]) { self.bytes = bytes }

    var fetches: Int { lock.withLock { counted } }

    func serve(_ url: URL, _ data: Data) { lock.withLock { bytes[url] = data } }

    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        lock.withLock { counted += 1 }
        if hangs { try await Task.sleep(for: .seconds(60)) }
        if fails { throw URLError(.notConnectedToInternet) }
        let data = try #require(lock.withLock { bytes[url] })
        progress(Int64(data.count) / 2)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination)
    }
}

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

    private func makeDownloader(_ fetcher: FakeFetcher) -> (VoiceModelDownloader, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (VoiceModelDownloader(storage: VoiceModelStorage(root: root), fetcher: fetcher), root)
    }

    @Test func downloadsEveryFileVerifiesAndMarksTheModelInstalled() async throws {
        let fetcher = FakeFetcher([first: hello, second: world])
        let (downloader, root) = makeDownloader(fetcher)
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
        #expect(fetcher.fetches == 2)
    }

    @Test func aWrongChecksumFailsAndOnlyThatFileIsFetchedAgain() async throws {
        let fetcher = FakeFetcher([first: hello, second: Data("WORLD!".utf8)])
        let (downloader, root) = makeDownloader(fetcher)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(secondSHA: sha(world))
        await downloader.start(model)?.value
        guard case .failed(let message) = downloader.state(for: model) else {
            Issue.record("expected a failed download, got \(downloader.state(for: model))")
            return
        }
        #expect(message.contains("two.bin"))
        #expect(!downloader.storage.isInstalled(model.id))
        #expect(fetcher.fetches == 2)
        fetcher.serve(second, world)
        await downloader.start(model)?.value
        #expect(downloader.state(for: model) == .installed)
        #expect(fetcher.fetches == 3, "the file that passed is kept")
    }

    @Test func aFileOfTheWrongSizeIsRefused() async throws {
        let fetcher = FakeFetcher([first: hello, second: Data("wor".utf8)])
        let (downloader, root) = makeDownloader(fetcher)
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
        let fetcher = FakeFetcher([first: hello, second: world])
        fetcher.fails = true
        let (downloader, root) = makeDownloader(fetcher)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        await downloader.start(model)?.value
        guard case .failed = downloader.state(for: model) else {
            Issue.record("expected a failed download")
            return
        }
        fetcher.fails = false
        await downloader.start(model)?.value
        #expect(downloader.state(for: model) == .installed)
    }

    @Test func cancelStopsTheDownloadAndRemovesWhatWasFetched() async throws {
        let fetcher = FakeFetcher([first: hello, second: world])
        fetcher.hangs = true
        let (downloader, root) = makeDownloader(fetcher)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let task = try #require(downloader.start(model))
        #expect(downloader.start(model) == nil, "a second Get while it runs does nothing")
        await Task.yield()
        downloader.cancel(model)
        await task.value
        #expect(downloader.state(for: model) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: downloader.storage.directory(for: model.id).path))
    }

    @Test func deleteRemovesAnInstalledModelAndCancelsARunningOne() async throws {
        let fetcher = FakeFetcher([first: hello, second: world])
        let (downloader, root) = makeDownloader(fetcher)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        await downloader.start(model)?.value
        try downloader.delete(model)
        #expect(downloader.state(for: model) == .notInstalled)
        #expect(!downloader.storage.isInstalled(model.id))

        fetcher.hangs = true
        let task = try #require(downloader.start(model))
        await Task.yield()
        try downloader.delete(model)
        await task.value
        #expect(downloader.state(for: model) == .notInstalled)
    }

    @Test func theSystemRowIsAlwaysInstalled() {
        let (downloader, root) = makeDownloader(FakeFetcher([:]))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(downloader.state(for: .system(.tts)) == .installed)
        #expect(downloader.start(.system(.tts)) == nil)
    }
}
