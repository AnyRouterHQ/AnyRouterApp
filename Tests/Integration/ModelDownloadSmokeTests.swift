import XCTest

@testable import AnyRouter

/// Drives the real `ModelDownloadManager` (background URLSession, Hugging Face listing, installer) with a ~1 MB model.
/// Skipped unless the smoke job runs, because it needs the network.
@MainActor
final class ModelDownloadSmokeTests: XCTestCase {
    func testDownloadManagerFetchesVerifiesAndInstallsATinyModel() async throws {
        try XCTSkipUnless(SmokeEnv.enabled, "ANYROUTER_SMOKE is not set. The download test runs only in model-smoke.yml.")
        let entry = CatalogEntry(
            repo: "ggml-org/tiny-llamas", format: .gguf, file: "stories260K.gguf", title: "Tiny", quantization: "F32")
        let storage = LocalModelStorage(root: makeTempDirectory())
        let manager = ModelDownloadManager(storage: storage)

        await manager.start(entry)
        let deadline = ContinuousClock.now + .seconds(180)
        var state = manager.state(for: entry)
        while ContinuousClock.now < deadline {
            state = manager.state(for: entry)
            if state == .installed { break }
            if case .failed(let message) = state {
                XCTFail("download failed: \(message)")
                SmokeReport.record("Download manager", "failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(state, .installed, "download did not finish in 180s, last state \(state)")
        guard state == .installed else {
            SmokeReport.record("Download manager", "did not finish in 180s, last state \(state)")
            return
        }

        let file = try XCTUnwrap(entry.file)
        let url = storage.fileURL(forEntryID: entry.id, path: file)
        let listing = try await HuggingFaceAPI().listFiles(repo: entry.repo, revision: "main")
        let listed = try XCTUnwrap(listing.first { $0.path == file }, "file missing from the HF listing")
        let expected = try XCTUnwrap(listed.sha256, "HF listed no sha256 for \(file), so the installer could not verify it")
        XCTAssertEqual(try ModelInstaller.sha256Hex(of: url), expected.lowercased())
        let onDisk = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).int64Value
        XCTAssertEqual(onDisk, listed.size)
        XCTAssertTrue(storage.isInstalled(entryID: entry.id))
        SmokeReport.record("Download manager", "background session downloaded \(file) (\(onDisk) bytes), size + sha256 \(expected.prefix(12)) verified, installed")
    }
}
