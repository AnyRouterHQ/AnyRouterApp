import Foundation
import Testing
@testable import AnyRouter

/// The Inkling 2 Mini catalog entry as the app reads it: the 1-bit name, the experimental badge, the sampling the
/// publisher recommends and the reply cap. The JSON is the family from catalog/dev-models.json with a neutral repo id.
struct InklingCatalogTests {
    private static let json = ##"""
    {"schemaVersion": 2, "updatedAt": "2026-11-27", "families": [{
      "id": "inkling-2", "name": "Inkling 2 Mini", "publisher": "Thinking Machines", "line": "inkling",
      "logo": "thinkingmachines", "summary": "S", "website": "https://huggingface.co/thinkingmachines/Inkling-2-Mini",
      "tags": ["thinking"], "badges": ["experimental"], "status": "current", "order": 9,
      "variants": [{
        "repo": "community/Inkling-2-Mini-GGUF", "engine": "gguf",
        "file": "Inkling-2-Mini-IQ1_S.gguf", "params": "26B", "quant": "1-bit",
        "sizeBytes": 6881463904, "contextLength": 1048576, "license": "apache-2.0",
        "revision": "309509848b3151419aa26d069eb03db57fd29a00",
        "sha256": "4d3cab7e88016548136e13f7ec465db7fc49ab8cf9559a60f3daad1f3f15c9d5",
        "vision": {"mmprojFile": "mmproj-Inkling-2-Mini-Q8_0.gguf", "mmprojSize": 345911008, "optional": true},
        "sampling": {"temperature": 1.0, "topP": 1.0, "topK": 0, "minP": 0.0, "maxOutputTokens": 1024},
        "memory": {"fullKVBytesPerToken": 16384, "windowKVBytesPerToken": 81920, "windowTokens": 1024,
                   "activeFraction": 0.119, "lazyWeightBytes": 260527104}
      }]
    }]}
    """##

    private func entry() throws -> CatalogEntry {
        try #require(try CatalogDocument.decode(Data(Self.json.utf8)).models.first)
    }

    @Test func theEntryNamesItselfOneBitAndShowsTheDownloadSize() throws {
        let entry = try entry()
        #expect(entry.sizeBytes == 6_881_463_904)
        #expect(entry.title == "Inkling 2 Mini 26B")
        #expect(entry.descriptor(isInstalled: false).displayName == "Inkling 2 Mini 26B (1-bit)")
        #expect(entry.supportsThinking)
        #expect(!entry.capabilities.contains("vision"), "text only until the person adds the projector")
    }

    @Test func thePhotoProjectorIsAnOptionalAddOnOfTheRealSize() throws {
        let entry = try entry()
        #expect(entry.vision?.isOptional == true)
        let addOn = try #require(entry.photoAddOn)
        #expect(addOn.sizeBytes == 345_911_008, "the size Hugging Face lists for the Q8_0 projector at the pinned revision")
        #expect(HubLogic.sizeText(addOn.sizeBytes) == "346 MB")
        #expect(entry.sizeBytes == 6_881_463_904, "the model's own download does not grow")
    }

    @Test func theFamilyBadgeReadsExperimentalAndSlowAsAWarning() throws {
        let entry = try entry()
        #expect(entry.badges == [CatalogBadge(label: "Experimental · slow", tone: "warning")])
    }

    @Test func theSamplingAndTheReplyCapSurviveARoundTrip() throws {
        let entry = try entry()
        let sampling = try #require(entry.sampling)
        #expect(sampling == CatalogSampling(temperature: 1.0, topP: 1.0, topK: 0, minP: 0, maxOutputTokens: 1024))
        let again = try JSONDecoder().decode(CatalogEntry.self, from: try JSONEncoder().encode(entry))
        #expect(again.sampling == sampling)
    }

    @Test func aDownloadLeavesAtLeastOneGigabyteFree() {
        #expect(ModelDownloadManager.spareBytes(forDownload: 7_764_293_056) == 1_000_000_000)
        #expect(ModelDownloadManager.spareBytes(forDownload: 20_000_000_000) == 2_000_000_000)
    }
}

/// The publisher's sampling replaces the app's settings for that model, and the cap only ever shortens a reply.
struct CatalogSamplingTests {
    @Test func setValuesReplaceTheAppDefaults() {
        var params = GenerationParams()
        params.temperature = 0.2
        params.topP = 0.5
        let sampling = CatalogSampling(temperature: 1.0, topP: 1.0)
        let tuned = sampling.applied(to: params)
        #expect(tuned.temperature == 1.0)
        #expect(tuned.topP == 1.0)
        #expect(tuned.maxTokens == nil)
    }

    @Test func missingValuesKeepTheAppSettings() {
        var params = GenerationParams()
        params.temperature = 0.3
        let tuned = CatalogSampling().applied(to: params)
        #expect(tuned.temperature == 0.3)
        #expect(tuned.topP == GenerationParams().topP)
    }

    @Test func theCapAppliesWithNoLimitAndNeverRaisesAShorterOne() {
        let cap = CatalogSampling(maxOutputTokens: 1024)
        #expect(cap.applied(to: GenerationParams()).maxTokens == 1024)
        var short = GenerationParams()
        short.maxTokens = 200
        #expect(cap.applied(to: short).maxTokens == 200)
        var long = GenerationParams()
        long.maxTokens = 4000
        #expect(cap.applied(to: long).maxTokens == 1024)
    }
}
