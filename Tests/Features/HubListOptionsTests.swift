import Foundation
import Testing
@testable import AnyRouter

struct HubListOptionsTests {
    private func entry(_ id: String, name: String? = nil, source: ModelSource = .gguf, size: Int64? = nil,
                       fit: ModelFit = .fits, caps: Set<String> = ["chat"], recommended: Bool = false,
                       unavailable: String? = nil, tags: [String] = []) -> LocalModelEntry {
        var d = testModel(id: id, source: source)
        d.displayName = name ?? id
        d.sizeBytes = size
        d.capabilities = caps
        return LocalModelEntry(descriptor: d, summary: "", tags: tags, fit: fit, isUserAdded: false,
                               unavailableReason: unavailable, isRecommended: recommended)
    }

    @Test func recommendedFirstThenCatalogOrder() {
        let list = [entry("a"), entry("b", recommended: true), entry("c"), entry("d", recommended: true)]
        let ids = HubListOptions.apply(list, sort: .recommended, filter: HubFilter()).map(\.id)
        #expect(ids == ["b", "d", "a", "c"])
    }

    @Test func sortsByNameAndSizeKeepingUnknownSizesLastWhenSmallestFirst() {
        let list = [entry("x", name: "banana", size: 300), entry("y", name: "Apple", size: nil), entry("z", name: "cherry", size: 100)]
        #expect(HubListOptions.apply(list, sort: .name, filter: HubFilter()).map(\.id) == ["y", "x", "z"])
        #expect(HubListOptions.apply(list, sort: .smallest, filter: HubFilter()).map(\.id) == ["z", "x", "y"])
        #expect(HubListOptions.apply(list, sort: .largest, filter: HubFilter()).map(\.id) == ["x", "z", "y"])
    }

    @Test func fitsOnlyHidesTooBigAndUnavailableModels() {
        let list = [entry("ok"), entry("tight", fit: .tight), entry("big", fit: .wontFit),
                    entry("mlx", source: .mlx, unavailable: "needs a GPU"), entry("unknown", fit: .unknown)]
        let kept = HubListOptions.apply(list, sort: .recommended, filter: HubFilter(fitsOnly: true)).map(\.id)
        #expect(kept == ["ok", "tight", "unknown"])
    }

    @Test func engineAndCapabilityFiltersCombine() {
        let list = [entry("g1", caps: ["chat", "vision"]), entry("g2"), entry("m1", source: .mlx, caps: ["chat", "vision"])]
        var filter = HubFilter()
        filter.engines = [.gguf]
        filter.capabilities = ["vision"]
        #expect(HubListOptions.apply(list, sort: .recommended, filter: filter).map(\.id) == ["g1"])
        #expect(filter.isActive)
        #expect(!HubFilter().isActive)
    }

    @Test func capabilityListSkipsPlainChat() {
        let list = [entry("a", caps: ["chat", "vision"]), entry("b", caps: ["chat", "tools", "vision"])]
        #expect(HubListOptions.capabilities(in: list) == ["tools", "vision"])
    }

    @Test func detailLineJoinsFormatTagsSizeAndMemory() {
        let detail = FitDetail(verdict: .fits, neededBytes: 3_100_000_000, budgetBytes: 6_000_000_000,
                               context: 8192, maxReply: 2048, streamsFromStorage: false, isEstimate: false)
        var e = entry("a", size: 2_500_000_000, tags: ["gguf", "4B", "Q4_K_M", "vision"])
        e.fitDetail = detail
        let line = HubListOptions.detailLine(e)
        #expect(line.hasPrefix("GGUF · 4B · Q4_K_M · "))
        #expect(line.hasSuffix("· Uses ~3.1 GB"))
    }

    @Test func fitStatusPrefersUnavailableReasonThenVerdict() {
        #expect(HubListOptions.fitStatus(entry("a", unavailable: "needs a GPU"), device: "iPhone") == "needs a GPU")
        #expect(HubListOptions.fitStatus(entry("a", fit: .wontFit), device: "iPhone") == "Too big for this iPhone")
        #expect(HubListOptions.fitStatus(entry("a", fit: .unknown), device: "iPhone") == nil)
    }

    @Test func storageSummaryHandlesUnknownFreeSpace() {
        #expect(HubListOptions.storageSummary(usedBytes: 6_900_000_000, freeBytes: 41_000_000_000) == "Models use 6.9 GB · 41.0 GB free")
        #expect(HubListOptions.storageSummary(usedBytes: 0, freeBytes: nil) == "Models use 0 MB")
    }
}
