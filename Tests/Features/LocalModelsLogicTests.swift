import Foundation
import Testing
@testable import AnyRouter

/// The Local Models screen's rules: storage, featured, and which sizes this device cannot run and why.
struct LocalModelsLogicTests {
    private func entry(
        _ id: String, name: String? = nil, size: Int64? = 1_000_000_000, fit: ModelFit = .fits, detail: FitDetail? = nil,
        blocked: String? = nil, family: String? = nil, source: ModelSource = .gguf, params: String? = nil,
        quant: String? = nil, deprecated: Bool = false
    ) -> LocalModelEntry {
        var descriptor = testModel(id: id, source: source)
        descriptor.displayName = name ?? id
        descriptor.sizeBytes = size
        return LocalModelEntry(
            descriptor: descriptor, summary: "S", tags: [], fit: fit, isUserAdded: false, unavailableReason: blocked,
            fitDetail: detail, familyID: family, familyName: family, parameters: params,
            parameterBillions: FamilyLogic.billions(of: params), quantization: quant, isDeprecated: deprecated)
    }

    private func wontFit(needed: Int64 = 3_900_000_000, budget: Int64 = 3_200_000_000) -> FitDetail {
        FitDetail(verdict: .wontFit, neededBytes: needed, budgetBytes: budget, context: 512, maxReply: 64,
                  streamsFromStorage: false, isEstimate: false)
    }

    private func states(_ table: [String: DownloadState]) -> (String) -> DownloadState {
        { table[$0] ?? .notInstalled }
    }

    // MARK: Installed and storage

    @Test func installedModelsAreListedAToZ() {
        let catalog = [entry("b", name: "banana"), entry("a", name: "Apple"), entry("c", name: "cherry")]
        let list = LocalModelsLogic.installed(catalog, state: states(["b": .installed, "a": .installed, "c": .notInstalled]))
        #expect(list.map(\.id) == ["a", "b"])
    }

    @Test func storageSumsTheInstalledFileSizes() {
        let installed = [entry("a", size: 1_500_000_000), entry("b", size: 600_000_000)]
        let storage = LocalModelsLogic.storage(installed: installed, freeBytes: 20_000_000_000)
        #expect(storage == .init(modelCount: 2, usedBytes: 2_100_000_000, freeBytes: 20_000_000_000))
        #expect(FitFormat.gigabytes(storage.usedBytes) == "2.1 GB")
    }

    @Test func aModelWithoutAKnownSizeCountsAsZero() {
        let storage = LocalModelsLogic.storage(installed: [entry("a", size: nil), entry("b", size: 500_000_000)], freeBytes: nil)
        #expect(storage.usedBytes == 500_000_000)
        #expect(storage.freeBytes == nil)
        #expect(LocalModelsLogic.storage(installed: [], freeBytes: nil) == .init(modelCount: 0, usedBytes: 0, freeBytes: nil))
    }

    @Test func deleteAllMessageSaysHowManyAndHowMuch() {
        let two = LocalModelsLogic.Storage(modelCount: 2, usedBytes: 2_100_000_000, freeBytes: nil)
        let one = LocalModelsLogic.Storage(modelCount: 1, usedBytes: 600_000_000, freeBytes: nil)
        #expect(LocalModelsLogic.deleteAllMessage(two, device: "iPhone")
            == "This removes 2 models (2.1 GB) from this iPhone. You can download them again later.")
        #expect(LocalModelsLogic.deleteAllMessage(one, device: "iPad")
            == "This removes 1 model (600 MB) from this iPad. You can download them again later.")
    }

    // MARK: Featured

    private func families(_ entries: [LocalModelEntry]) -> [LocalModelFamily] { FamilyLogic.families(from: entries) }

    @Test func featuredIsEachFamilysBestSizeWithoutWhatIsInstalled() {
        let entries = [
            entry("a1", family: "a", params: "1B"), entry("a4", family: "a", params: "4B"),
            entry("b1", family: "b", params: "1B"), entry("c1", family: "c", params: "2B"),
        ]
        let all = families(entries)
        #expect(LocalModelsLogic.featured(families: all, state: states([:])).map(\.id) == ["a4", "c1", "b1"])
        let withInstalled = states(["a4": .installed])
        #expect(LocalModelsLogic.featured(families: all, state: withInstalled).map(\.id) == ["c1", "b1"],
                "an installed size moves to Installed, its family does not offer a smaller one")
    }

    @Test func aDownloadInFlightStaysFeaturedSoItsProgressShowsWhereGetWas() {
        let all = families([entry("a1", family: "a", params: "1B")])
        #expect(LocalModelsLogic.featured(families: all, state: states(["a1": .downloading(progress: 0.4)])).map(\.id) == ["a1"])
    }

    @Test func featuredIsCappedAndNeverNegative() {
        let all = families([entry("a", family: "a", params: "1B"), entry("b", family: "b", params: "2B"), entry("c", family: "c", params: "3B")])
        #expect(LocalModelsLogic.featured(families: all, state: states([:]), limit: 2).count == 2)
        #expect(LocalModelsLogic.featured(families: all, state: states([:]), limit: -1).isEmpty)
    }

    // MARK: Unavailable

    @Test func aModelThatWillNotFitSaysWhatItNeedsAndWhatTheDeviceAllows() {
        let big = entry("big", fit: .wontFit, detail: wontFit())
        let list = LocalModelsLogic.unavailable(catalog: [big], state: states([:]), device: "iPhone")
        #expect(list.map(\.id) == ["big"])
        #expect(list[0].reason == "Needs about 3.9 GB, this iPhone allows 3.2 GB.")
    }

    @Test func aFileBiggerThanTheAddressSpaceSaysSoAndWhatSigningFixesIt() {
        var detail = wontFit(needed: 3_000_000_000, budget: 8_000_000_000)
        detail.mappableBytes = 4_200_000_000
        let list = LocalModelsLogic.unavailable(catalog: [entry("big", fit: .wontFit, detail: detail)], state: states([:]), device: "iPhone")
        #expect(list.first?.reason == "This install can open files up to 4.2 GB at once. \(FitText.addressSpaceFix)",
                "memory is not the reason here, so it must not be named")
    }

    @Test func aBlockedModelShowsItsOwnReason() {
        let mlx = entry("mlx/x", fit: .fits, blocked: "MLX models need a physical device.", source: .mlx)
        #expect(LocalModelsLogic.unavailable(catalog: [mlx], state: states([:]), device: "iPhone").first?.reason
            == "MLX models need a physical device.")
    }

    @Test func aModelKnownToBeTooBigWithoutNumbersStillGetsAReason() {
        let list = LocalModelsLogic.unavailable(catalog: [entry("x", fit: .wontFit)], state: states([:]), device: "iPad")
        #expect(list.first?.reason == "Too big for this iPad.")
    }

    @Test func modelsThatRunAreNotListedAndTightOnesRun() {
        let catalog = [
            entry("fits", fit: .fits), entry("tight", fit: .tight), entry("unknown", fit: .unknown),
            entry("installed", fit: .wontFit, detail: wontFit()), entry("old", fit: .wontFit, deprecated: true),
            entry("gone", fit: .wontFit, detail: wontFit()),
        ]
        let list = LocalModelsLogic.unavailable(catalog: catalog, state: states(["installed": .installed]), device: "iPhone")
        #expect(list.map(\.id) == ["gone"])
        #expect(LocalModelsLogic.reason(for: entry("fits"), device: "iPhone") == nil)
    }

    @Test func theMoreMemoryTheFewerModelsAreUnavailable() {
        // The same catalog judged with two budgets: the bigger device lists fewer sizes.
        func list(budget: Int64) -> [String] {
            let sizes: [(String, Int64)] = [("small", 2_000_000_000), ("medium", 4_000_000_000), ("large", 7_000_000_000)]
            let catalog = sizes.map { id, needed in
                entry(id, fit: needed > budget ? .wontFit : .fits, detail: needed > budget ? wontFit(needed: needed, budget: budget) : nil)
            }
            return LocalModelsLogic.unavailable(catalog: catalog, state: states([:]), device: "iPhone").map(\.id)
        }
        #expect(list(budget: 3_200_000_000) == ["medium", "large"])
        #expect(list(budget: 8_000_000_000).isEmpty)
    }

    @Test func titleNamesTheDeviceAndTheCount() {
        #expect(LocalModelsLogic.unavailableTitle(count: 3, device: "iPhone") == "Not available on this iPhone (3)")
    }

    // MARK: Row text

    @Test func fileLineShowsFormatSizeAndQuantizationButNotTheMemoryEstimate() {
        let full = entry("a", size: 2_500_000_000, detail: wontFit(), params: "4B", quant: "Q4_K_M")
        #expect(LocalModelsLogic.fileLine(full) == "GGUF · 4B · Q4_K_M · 2.5 GB")
        #expect(LocalModelsLogic.fileLine(entry("b", size: nil, source: .mlx)) == "MLX")
    }

    @Test func appleStatusIsReadyOrSaysWhyNot() {
        var apple = testModel(id: "apple/foundation", source: .apple)
        #expect(LocalModelsLogic.appleStatus(apple) == "Available · Built in")
        apple.isInstalled = false
        #expect(LocalModelsLogic.appleStatus(apple) == "Not available on this device")
        apple.summary = "Turn on Apple Intelligence in Settings."
        #expect(LocalModelsLogic.appleStatus(apple) == "Not available · Turn on Apple Intelligence in Settings.")
    }

    @Test func theFooterWarnsAboutAccuracyAndNamesHuggingFace() {
        #expect(LocalModelsLogic.disclaimer.contains("inaccurate or incomplete"))
        #expect(LocalModelsLogic.disclaimer.contains("Double-check"))
        #expect(LocalModelsLogic.disclaimer.contains("Hugging Face"))
    }
}

@MainActor
struct DeleteAllModelsTests {
    /// A hub whose installed set shrinks as models are deleted.
    @MainActor @Observable
    final class RecordingHub: ModelHubService {
        var catalog: [LocalModelEntry]
        var lastError: String?
        var remoteCatalogURL = ""
        var usesDevelopmentCatalog = false
        var memoryLimitNote: String?
        var installed: Set<String>
        var deleted: [String] = []
        var removedUserModels: [String] = []

        init(catalog: [LocalModelEntry], installed: Set<String>) {
            self.catalog = catalog
            self.installed = installed
        }

        func refreshCatalog() async {}
        func setUsesDevelopmentCatalog(_ on: Bool) async {}
        func reload() async {}
        func downloadState(for modelID: String) -> DownloadState { installed.contains(modelID) ? .installed : .notInstalled }
        func download(_ entry: LocalModelEntry) {}
        func pause(modelID: String) {}
        func resume(modelID: String) {}
        func cancel(modelID: String) {}
        func delete(modelID: String) async { installed.remove(modelID); deleted.append(modelID) }
        func searchRepos(_ query: String) async throws -> [RepoHit] { [] }
        func entries(for hit: RepoHit) async throws -> [LocalModelEntry] { [] }
        func addRepo(_ hit: RepoHit) async throws {}
        func removeUserModel(modelID: String) async { removedUserModels.append(modelID) }
        func setRemoteCatalogURL(_ text: String) async throws {}
    }

    private func entry(_ id: String) -> LocalModelEntry {
        LocalModelEntry(descriptor: testModel(id: id, source: .gguf), summary: "", tags: [], fit: .fits, isUserAdded: false)
    }

    @Test func deleteAllRemovesEveryInstalledModelAndLeavesTheRest() async {
        let hub = RecordingHub(catalog: [entry("a"), entry("b"), entry("c")], installed: ["a", "c"])
        await hub.deleteAllModels()
        #expect(hub.deleted.sorted() == ["a", "c"])
        #expect(hub.installed.isEmpty)
        #expect(LocalModelsLogic.installed(hub.catalog, state: { hub.downloadState(for: $0) }).isEmpty)
    }

    @Test func deleteAllWithNothingInstalledDoesNothing() async {
        let hub = RecordingHub(catalog: [entry("a")], installed: [])
        await hub.deleteAllModels()
        #expect(hub.deleted.isEmpty)
    }

    @Test func removingSeveralUserModelsRemovesEachOne() async {
        let hub = RecordingHub(catalog: [], installed: [])
        await hub.removeUserModels(["x", "y"])
        #expect(hub.removedUserModels == ["x", "y"])
    }
}
