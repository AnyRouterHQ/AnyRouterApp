import XCTest

@testable import AnyRouter

/// The download path with a ~1 MB model, over the real Hugging Face API.
///
/// `ModelDownloadManager` itself cannot run here: its background `URLSession` needs `nsurlsessiond`, which is
/// not reachable from a Simulator test host (`BackgroundSession ... connection to service named
/// com.apple.nsurlsessiond`, seen in the first model-smoke run). So this test runs the same steps the manager runs
/// with a foreground session: file listing, `RepoFiles.downloadPlan`, download, `ModelInstaller.verifyAndInstall`.
/// Background downloads stay device-only (PLAN F1).
final class ModelDownloadSmokeTests: XCTestCase {
    func testListingDownloadAndInstallerVerifyATinyModel() async throws {
        try XCTSkipUnless(SmokeEnv.enabled, "ANYROUTER_SMOKE is not set. The download test runs only in model-smoke.yml.")
        let entry = CatalogEntry(
            repo: "ggml-org/tiny-llamas", format: .gguf, file: "stories260K.gguf", title: "Tiny", quantization: "F32")
        let storage = LocalModelStorage(root: makeTempDirectory())
        let api = HuggingFaceAPI()

        let listing = try await api.listFiles(repo: entry.repo, revision: "main")
        let plan = try RepoFiles.downloadPlan(for: entry, files: listing)
        let file = try XCTUnwrap(plan.first)
        let expectedSHA = try XCTUnwrap(file.sha256, "HF listed no sha256 for \(file.path), so nothing could be verified")

        let (tempURL, response) = try await URLSession.shared.download(
            from: api.resolveURL(repo: entry.repo, revision: "main", path: file.path))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let partial = storage.partialFileURL(forEntryID: entry.id, path: file.path)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: tempURL, to: partial)

        try ModelInstaller.verifyAndInstall(DownloadJobRecord(entry: entry, files: plan), storage: storage)
        XCTAssertTrue(storage.isInstalled(entryID: entry.id))
        let installed = storage.fileURL(forEntryID: entry.id, path: file.path)
        XCTAssertEqual(try ModelInstaller.sha256Hex(of: installed), expectedSHA.lowercased())
        SmokeReport.record(
            "Download path",
            "listing, plan, foreground download and installer verified \(file.path) (\(file.size) bytes, sha256 \(expectedSHA.prefix(12))). ModelDownloadManager's background session cannot run in a Simulator test host (nsurlsessiond unreachable): device only")
    }
}
