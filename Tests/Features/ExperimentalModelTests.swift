import Foundation
import Testing
@testable import AnyRouter

/// An experimental family (Inkling 2 Mini 1-bit) in Local Models: Featured on every device after the picks, never as a
/// pick, and where the estimate doubts it, a quiet line that names the RAM instead of a block.
struct ExperimentalModelTests {
    private let experimentalBadge = CatalogBadge.experimental.label.lowercased()

    private func entry(_ id: String, family: String, params: String, fit: ModelFit, detail: FitDetail? = nil) -> LocalModelEntry {
        LocalModelEntry(
            descriptor: testModel(id: id, source: .gguf), summary: "S", tags: [], fit: fit, isUserAdded: false,
            fitDetail: detail, familyID: family, familyName: family, parameters: params,
            parameterBillions: FamilyLogic.billions(of: params))
    }

    private func family(_ id: String, badges: [String] = [], variants: [LocalModelEntry]) -> LocalModelFamily {
        LocalModelFamily(id: id, name: id, publisher: "Pub", logo: "logo", summary: "S", website: nil, tags: [], badges: badges,
                         variants: variants)
    }

    private func states(_ table: [String: DownloadState]) -> (String) -> DownloadState {
        { table[$0] ?? .notInstalled }
    }

    @Test func theCatalogBadgeMakesAFamilyExperimental() {
        #expect(FamilyLogic.isExperimental(family("x", badges: [experimentalBadge], variants: [])))
        #expect(!FamilyLogic.isExperimental(family("y", badges: ["new"], variants: [])))
    }

    @Test func aStreamingDeviceFindsItAfterThePicksOutsideTheLimit() {
        let picks = (1...3).map { family("p\($0)", variants: [entry("p\($0)", family: "p\($0)", params: "\($0)B", fit: .fits)]) }
        let inkling = family("inkling", badges: [experimentalBadge], variants: [entry("ink", family: "inkling", params: "26B", fit: .tight)])
        let featured = LocalModelsLogic.featured(families: picks + [inkling], state: states([:]), limit: 3)
        #expect(featured.map(\.id) == ["p3", "p2", "p1", "ink"])
    }

    @Test func itIsNeverAPickEvenWhereItRunsWell() {
        // An iPad Pro with the increased limit holds the whole file: it still follows the picks, it does not lead them.
        let small = family("small", variants: [entry("s", family: "small", params: "2B", fit: .fits)])
        let inkling = family("inkling", badges: [experimentalBadge], variants: [entry("ink", family: "inkling", params: "26B", fit: .fits)])
        #expect(LocalModelsLogic.featured(families: [inkling, small], state: states([:])).map(\.id) == ["s", "ink"])
    }

    /// The estimate once hid Inkling from a phone that runs it. Now only the install (or an engine that cannot run here)
    /// takes it out of Featured.
    @Test func itIsFeaturedEvenWhereTheEstimateDoubtsItButNotOnceInstalled() {
        let inkling = family("inkling", badges: [experimentalBadge], variants: [entry("ink", family: "inkling", params: "26B", fit: .wontFit)])
        #expect(LocalModelsLogic.featured(families: [inkling], state: states([:])).map(\.id) == ["ink"])
        #expect(LocalModelsLogic.featured(families: [inkling], state: states(["ink": .installed])).isEmpty)
        var blocked = entry("ink", family: "inkling", params: "26B", fit: .fits)
        blocked.unavailableReason = "MLX needs a device"
        #expect(LocalModelsLogic.featured(families: [family("inkling", badges: [experimentalBadge], variants: [blocked])], state: states([:])).isEmpty)
    }

    @Test func belowTheStreamingClassTheQuietLineNamesTheRAM() {
        let detail = FitDetail(verdict: .wontFit, neededBytes: 8_700_000_000, budgetBytes: 3_100_000_000, context: 512,
                               maxReply: 64, streamsFromStorage: false, isEstimate: false, streamsWithRAMGigabytes: 12)
        #expect(FitText.badge(detail, device: "iPhone") == "May not load on this iPhone")
        #expect(FitText.explanation(detail, device: "iPad") == "Streaming it is planned for an iPad with 12 GB of memory.")
    }
}
