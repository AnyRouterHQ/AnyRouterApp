import Foundation
import Testing
@testable import AnyRouter

struct HubListOptionsTests {
    private func entry(_ id: String, source: ModelSource = .gguf, size: Int64? = nil, fit: ModelFit = .fits,
                       unavailable: String? = nil, parameters: String? = nil, quantization: String? = nil) -> LocalModelEntry {
        var d = testModel(id: id, source: source)
        d.sizeBytes = size
        return LocalModelEntry(descriptor: d, summary: "", tags: [], fit: fit, isUserAdded: false,
                               unavailableReason: unavailable, parameters: parameters, quantization: quantization)
    }

    private func family(name: String, publisher: String = "", summary: String = "", tags: [String] = []) -> LocalModelFamily {
        LocalModelFamily(id: name, name: name, publisher: publisher, logo: "", summary: summary, website: nil,
                         tags: tags, badges: [], variants: [])
    }

    @Test func familySearchMatchesNamePublisherSummaryAndTags() {
        let f = family(name: "Gemma 4", publisher: "Google", summary: "Small and quick", tags: ["vision"])
        #expect(HubListOptions.matches(f, "gem"))
        #expect(HubListOptions.matches(f, "GOOGLE"))
        #expect(HubListOptions.matches(f, "quick"))
        #expect(HubListOptions.matches(f, "vision"))
        #expect(!HubListOptions.matches(f, "llama"))
    }

    @Test func detailLineJoinsFormatParametersQuantizationSizeAndMemory() {
        let detail = FitDetail(verdict: .fits, neededBytes: 3_100_000_000, budgetBytes: 6_000_000_000,
                               context: 8192, maxReply: 2048, streamsFromStorage: false, isEstimate: false)
        var e = entry("a", size: 2_500_000_000, parameters: "4B", quantization: "Q4_K_M")
        e.fitDetail = detail
        let line = HubListOptions.detailLine(e)
        #expect(line.hasPrefix("GGUF · 4B · Q4_K_M · "))
        #expect(line.hasSuffix("· Uses ~3.1 GB"))
    }

    @Test func fitStatusPrefersUnavailableReasonThenVerdict() {
        #expect(HubListOptions.fitStatus(entry("a", unavailable: "needs a GPU"), device: "iPhone") == "needs a GPU")
        #expect(HubListOptions.fitStatus(entry("a", fit: .tight), device: "iPhone") == "May be slow")
        #expect(HubListOptions.fitStatus(entry("a", fit: .wontFit), device: "iPhone") == "Too big for this iPhone")
        #expect(HubListOptions.fitStatus(entry("a", fit: .unknown), device: "iPhone") == nil)
    }

    @Test func storageSummaryHandlesUnknownFreeSpace() {
        #expect(HubListOptions.storageSummary(usedBytes: 6_900_000_000, freeBytes: 41_000_000_000) == "Models use 6.9 GB · 41.0 GB free")
        #expect(HubListOptions.storageSummary(usedBytes: 0, freeBytes: nil) == "Models use 0 MB")
    }
}
