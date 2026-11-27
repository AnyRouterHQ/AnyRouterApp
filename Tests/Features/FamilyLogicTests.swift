import Foundation
import Testing
@testable import AnyRouter

struct FamilyLogicTests {
    // MARK: Builders

    private func entry(
        _ id: String, family: String? = "fam", name: String = "Fam", source: ModelSource = .gguf, params: String = "1B",
        size: Int64 = 1_000_000_000, fit: ModelFit = .fits, deprecated: Bool = false, released: String? = nil,
        capabilities: Set<String> = ["chat"], badges: [ModelBadge] = [], unavailable: String? = nil
    ) -> LocalModelEntry {
        var descriptor = testModel(id: id, source: source)
        descriptor.sizeBytes = size
        descriptor.capabilities = capabilities
        return LocalModelEntry(
            descriptor: descriptor, summary: "S", tags: [], fit: fit, isUserAdded: false, unavailableReason: unavailable,
            badges: badges, familyID: family, familyName: family == nil ? nil : name, publisher: "Pub", logo: "logo",
            website: "https://example.org", parameters: params, parameterBillions: FamilyLogic.billions(of: params),
            releasedAt: released, isDeprecated: deprecated)
    }

    private func family(
        _ id: String, name: String? = nil, badges: [String] = [], tags: [String] = [], variants: [LocalModelEntry]
    ) -> LocalModelFamily {
        LocalModelFamily(
            id: id, name: name ?? id, publisher: "Pub", logo: "logo", summary: "S", website: nil, tags: tags, badges: badges,
            variants: variants)
    }

    /// The bundled catalog's current families, with each size judged by `FitPlanner` over a device class.
    private func families(_ deviceClass: DeviceClass, _ kind: MemoryLimitKind) throws -> [LocalModelFamily] {
        let memory = deviceClass.memory(kind)
        let entries = try BundledCatalog.load().models.map { model -> LocalModelEntry in
            let fit: ModelFit
            switch model.memoryProfile.map({ FitPlanner.estimate($0, memory: memory) })?.verdict {
            case .runsWell?: fit = .fits
            case .tight?, .streamed?: fit = .tight
            case .wontFit?: fit = .wontFit
            case nil: fit = .unknown
            }
            return LocalModelEntry(
                descriptor: model.descriptor(isInstalled: false), summary: "", tags: [], fit: fit, isUserAdded: false,
                badges: model.badges.map { ModelBadge(label: $0.label) }, familyID: model.familyID,
                familyName: model.familyName, parameters: model.parameters,
                parameterBillions: FamilyLogic.billions(of: model.parameters), isDeprecated: model.status == .deprecated)
        }
        return FamilyLogic.families(from: entries)
    }

    // MARK: Grouping

    @Test func entriesAreGroupedByFamilyInCatalogOrderAndDeprecatedOnesAreLeftOut() {
        let entries = [
            entry("a1", family: "a", name: "Alpha", capabilities: ["chat", "reasoning", "vision"], badges: [ModelBadge(label: "New")]),
            entry("b1", family: "b", name: "Beta"),
            entry("a2", family: "a", name: "Alpha"),
            entry("old", family: "c", name: "Old", deprecated: true),
            entry("mine", family: nil),
        ]
        let families = FamilyLogic.families(from: entries)
        #expect(families.map(\.id) == ["a", "b"])
        #expect(families[0].variants.map(\.id) == ["a1", "a2"])
        #expect(families[0].name == "Alpha" && families[0].publisher == "Pub" && families[0].logo == "logo")
        #expect(families[0].tags == ["thinking", "vision"], "the reasoning capability is the thinking tag")
        #expect(families[0].badges == ["new"])
        #expect(families[0].website == "https://example.org")
        #expect(FamilyLogic.ungrouped(entries).map(\.id) == ["mine"])
    }

    @Test func aFamilyWithoutANameOrPublisherFallsBackToItsID() {
        var bare = entry("x", family: "fallback")
        bare.familyName = nil
        bare.publisher = nil
        bare.logo = nil
        let family = FamilyLogic.families(from: [bare])[0]
        #expect(family.name == "fallback" && family.publisher.isEmpty && family.logo.isEmpty)
    }

    @Test func theBundledCatalogMakesCurrentFamiliesAndHidesTheOldGenerations() throws {
        let entries = try BundledCatalog.load().models.map { model in
            LocalModelEntry(
                descriptor: model.descriptor(isInstalled: false), summary: model.summary ?? "", tags: [], fit: .fits,
                isUserAdded: false, familyID: model.familyID, familyName: model.familyName, isDeprecated: model.status == .deprecated)
        }
        let ids = FamilyLogic.families(from: entries).map(\.id)
        #expect(ids.contains("gemma-4") && ids.contains("qwen-3-5"))
        #expect(!ids.contains("gemma-3") && !ids.contains("qwen-3") && !ids.contains("llama-3-2"))
    }

    // MARK: Sizes

    @Test func parameterCountsReadAsBillions() {
        #expect(FamilyLogic.billions(of: "4B") == 4)
        #expect(FamilyLogic.billions(of: "E2B") == 2)
        #expect(FamilyLogic.billions(of: "0.6B") == 0.6)
        #expect(FamilyLogic.billions(of: "700M") == 0.7)
        #expect(FamilyLogic.billions(of: " 8b ") == 8)
        #expect(FamilyLogic.billions(of: "XL") == nil)
        #expect(FamilyLogic.billions(of: "0B") == nil)
        #expect(FamilyLogic.billions(of: "B") == nil)
        #expect(FamilyLogic.billions(of: nil) == nil)
    }

    // MARK: Fit summary

    @Test func theFamilyRowSaysHowManySizesFit() {
        let fits = entry("1"), tight = entry("2", fit: .tight), big = entry("3", fit: .wontFit)
        #expect(FamilyLogic.fitSummary(family("f", variants: [fits, tight, big]), device: "iPhone") == "2 of 3 sizes fit")
        #expect(FamilyLogic.fitSummary(family("f", variants: [fits, tight]), device: "iPhone") == "All 2 sizes fit")
        #expect(FamilyLogic.fitSummary(family("f", variants: [fits]), device: "iPad") == "Fits this iPad")
        #expect(FamilyLogic.fitSummary(family("f", variants: [big]), device: "iPhone") == "No size fits this iPhone")
        #expect(FamilyLogic.fitSummary(family("f", variants: [entry("4", unavailable: "needs a GPU")]), device: "iPhone")
            == "No size fits this iPhone", "a size blocked for another reason does not count")
    }

    // MARK: Recommended

    @Test func theBiggestSizeThatRunsWellIsRecommendedAndAFileThatOnlyFitsTightlyIsNot() {
        let small = entry("small", params: "2B", size: 1)
        let big = entry("big", params: "4B", size: 2)
        let tight = entry("tight", params: "8B", size: 3, fit: .tight)
        #expect(FamilyLogic.recommendedVariantID(in: family("f", variants: [small, big, tight])) == "big")
        #expect(FamilyLogic.recommendedVariantID(in: family("f", variants: [entry("t", fit: .tight), entry("w", fit: .wontFit)])) == nil)
    }

    @Test func atTheSameModelSizeGGUFWinsThenTheLargerFile() {
        let mlx = entry("mlx", source: .mlx, params: "4B", size: 5)
        let gguf = entry("gguf", source: .gguf, params: "4B", size: 3)
        #expect(FamilyLogic.recommendedVariantID(in: family("f", variants: [mlx, gguf])) == "gguf")
        let bigger = entry("bigger", source: .gguf, params: "4B", size: 4)
        #expect(FamilyLogic.recommendedVariantID(in: family("f", variants: [gguf, bigger])) == "bigger")
    }

    @Test func aSizeBlockedForAnotherReasonIsNeverRecommended() {
        let blocked = entry("blocked", params: "8B", unavailable: "MLX needs a GPU")
        let ok = entry("ok", params: "1B")
        #expect(FamilyLogic.recommendedVariantID(in: family("f", variants: [blocked, ok])) == "ok")
    }

    /// The real catalog on one device class: the recommended size of each family.
    /// "none" when no size of the family runs well.
    private func recommended(_ deviceClass: DeviceClass, _ kind: MemoryLimitKind) throws -> [String: String] {
        let list = try families(deviceClass, kind)
        return Dictionary(uniqueKeysWithValues: list.map { family in
            (family.id, FamilyLogic.recommendedVariantID(in: family).map { id in
                family.variants.first { $0.id == id }.map { "\($0.parameters ?? "")/\($0.descriptor.source.rawValue)" } ?? id
            } ?? "none")
        })
    }

    @Test func theRecommendedSizeGrowsWithTheDevicesMemory() throws {
        // A sideloaded install has the standard limit.
        #expect(try recommended(.gb4, .standard) == ["gemma-4": "none", "qwen-3-5": "none"])
        #expect(try recommended(.gb6, .standard) == ["gemma-4": "none", "qwen-3-5": "0.8B/gguf"])
        #expect(try recommended(.gb8, .standard) == ["gemma-4": "E2B/gguf", "qwen-3-5": "2B/gguf"])
        #expect(try recommended(.gb12, .standard) == ["gemma-4": "E2B/gguf", "qwen-3-5": "2B/gguf"])
        #expect(try recommended(.gb16, .standard) == ["gemma-4": "E2B/gguf", "qwen-3-5": "2B/gguf"])
        // TestFlight and App Store builds have the increased limit.
        #expect(try recommended(.gb4, .increased) == ["gemma-4": "none", "qwen-3-5": "0.8B/gguf"])
        #expect(try recommended(.gb6, .increased) == ["gemma-4": "E2B/gguf", "qwen-3-5": "2B/gguf"])
        #expect(try recommended(.gb8, .increased) == ["gemma-4": "E4B/gguf", "qwen-3-5": "4B/gguf"])
        #expect(try recommended(.gb12, .increased) == ["gemma-4": "E4B/gguf", "qwen-3-5": "4B/gguf"])
        #expect(try recommended(.gb16, .increased) == ["gemma-4": "E4B/gguf", "qwen-3-5": "4B/gguf"])
    }

    // MARK: Short list

    @Test func theShortListHasTopPicksFirstThenTheBiggerModelAndHonorsTheLimit() {
        let pick = family("pick", badges: ["recommended"], variants: [entry("pick-2b", params: "2B", size: 2)])
        let big = family("big", variants: [entry("big-4b", params: "4B", size: 4)])
        let small = family("small", variants: [entry("small-1b", params: "1B", size: 1)])
        let tooBig = family("too-big", variants: [entry("huge", params: "27B", fit: .wontFit)])
        let sameA = family("same-a", variants: [entry("same-a-1b", params: "1B", size: 1)])
        let all = [small, tooBig, big, pick, sameA]
        #expect(FamilyLogic.recommendedEntries(from: all).map(\.id) == ["pick-2b", "big-4b", "small-1b", "same-a-1b"])
        #expect(FamilyLogic.recommendedEntries(from: all, limit: 2).map(\.id) == ["pick-2b", "big-4b"])
        #expect(FamilyLogic.recommendedEntries(from: all, limit: 0).isEmpty)
        #expect(FamilyLogic.recommendedEntries(from: [tooBig]).isEmpty, "nothing runs well: no section")
    }

    @Test func theShortListOnEachDeviceClassLeadsWithGemma4WhenItRunsWell() throws {
        func lead(_ deviceClass: DeviceClass, _ kind: MemoryLimitKind) throws -> [String] {
            FamilyLogic.recommendedEntries(from: try families(deviceClass, kind)).map {
                "\($0.familyName ?? "")/\($0.parameters ?? "")/\($0.descriptor.source.rawValue)"
            }
        }
        #expect(try lead(.gb4, .increased) == ["Qwen 3.5/0.8B/gguf"])
        #expect(try lead(.gb6, .increased) == ["Gemma 4/E2B/gguf", "Qwen 3.5/2B/gguf"])
        #expect(try lead(.gb8, .increased) == ["Gemma 4/E4B/gguf", "Qwen 3.5/4B/gguf"])
        #expect(try lead(.gb12, .standard) == ["Gemma 4/E2B/gguf", "Qwen 3.5/2B/gguf"])
        #expect(try lead(.gb4, .standard).isEmpty)
    }

    // MARK: Sort

    private var sample: [LocalModelFamily] {
        [
            family("plain-big", name: "Plain Big", variants: [entry("p1", size: 5_000_000_000, released: "2026-01-01")]),
            family("pick", name: "Zeta Pick", badges: ["recommended"], variants: [entry("k1", size: 3_000_000_000, released: "2026-03-01")]),
            family("runs", name: "Alpha Runs", variants: [entry("r1", size: 500_000_000, released: "2026-02-01")]),
            family("tie", name: "alpha tie", variants: [entry("t1", size: 500_000_000, released: "2026-02-01")]),
            family("none", name: "None", variants: [entry("n1", size: 9_000_000_000, fit: .wontFit)]),
        ]
    }

    private func ids(_ sort: FamilySort, filter: FamilyFilter = FamilyFilter(fitsOnly: false)) -> [String] {
        FamilyLogic.apply(sample, sort: sort, filter: filter).map(\.id)
    }

    @Test func recommendedPutsTopPicksFirstThenFamiliesThatRunWellThenTheRestInCatalogOrder() {
        #expect(ids(.recommended) == ["pick", "plain-big", "runs", "tie", "none"])
    }

    @Test func smallestOrdersBySmallestSizeAndKeepsCatalogOrderOnATie() {
        #expect(ids(.smallest) == ["runs", "tie", "pick", "plain-big", "none"])
    }

    @Test func newestPutsTheMostRecentlyUpdatedFirstAndKeepsCatalogOrderOnATie() {
        #expect(ids(.newest) == ["pick", "runs", "tie", "plain-big", "none"])
    }

    @Test func nameIgnoresCaseAndKeepsCatalogOrderOnATie() {
        #expect(ids(.name) == ["runs", "tie", "none", "plain-big", "pick"])
        let twins = [family("second", name: "Same", variants: [entry("a")]), family("first", name: "same", variants: [entry("b")])]
        #expect(FamilyLogic.apply(twins, sort: .name, filter: FamilyFilter()).map(\.id) == ["second", "first"])
    }

    @Test func aFamilyWithoutSizesOrDatesSortsLast() {
        let empty = family("empty", variants: [])
        #expect(FamilyLogic.smallestSize(empty) == .max)
        #expect(FamilyLogic.newestDate(empty).isEmpty)
        #expect(!FamilyLogic.isTopPick(empty))
        #expect(FamilyLogic.isTopPick(family("best", badges: ["best"], variants: [])))
    }

    @Test func sortTitlesAreWhatTheMenuShows() {
        #expect(FamilySort.allCases.map(\.title) == ["Recommended", "Smallest", "Newest", "Name"])
        #expect(FamilySort.allCases.map(\.id) == ["recommended", "smallest", "newest", "name"])
    }

    // MARK: Filter

    @Test func fitsThisDeviceIsOnByDefaultAndHidesFamiliesWhereNothingFits() {
        let defaults = FamilyLogic.apply(sample, sort: .recommended, filter: FamilyFilter()).map(\.id)
        #expect(!defaults.contains("none") && defaults.count == 4)
        #expect(FamilyFilter().fitsOnly)
        #expect(!FamilyFilter().isChanged)
        #expect(FamilyFilter(fitsOnly: false).isChanged)
    }

    @Test func engineFilterKeepsFamiliesThatHaveThatEngine() {
        let both = family("both", variants: [entry("g", source: .gguf), entry("m", source: .mlx)])
        let ggufOnly = family("g", variants: [entry("g2", source: .gguf)])
        let filter = FamilyFilter(engines: [.mlx])
        #expect(FamilyLogic.apply([both, ggufOnly], sort: .name, filter: filter).map(\.id) == ["both"])
        #expect(FamilyLogic.variants(of: both, filter: filter).map(\.id) == ["m"])
    }

    @Test func tagFilterNeedsEveryChosenTag() {
        let both = family("both", tags: ["thinking", "vision"], variants: [entry("a")])
        let one = family("one", tags: ["thinking"], variants: [entry("b")])
        #expect(FamilyLogic.apply([both, one], sort: .name, filter: FamilyFilter(tags: ["thinking"])).map(\.id) == ["both", "one"])
        #expect(FamilyLogic.apply([both, one], sort: .name, filter: FamilyFilter(tags: ["thinking", "vision"])).map(\.id) == ["both"])
        #expect(FamilyLogic.tags(in: [both, one]) == ["thinking", "vision"])
    }

    @Test func sizeBucketsUseDecimalGigabytes() {
        #expect(SizeBucket.underOneGB.contains(999_999_999) && !SizeBucket.underOneGB.contains(1_000_000_000))
        #expect(SizeBucket.oneToFourGB.contains(1_000_000_000) && SizeBucket.oneToFourGB.contains(3_999_999_999))
        #expect(!SizeBucket.oneToFourGB.contains(4_000_000_000) && SizeBucket.overFourGB.contains(4_000_000_000))
        #expect(SizeBucket.allCases.map(\.title) == ["Under 1 GB", "1 to 4 GB", "Over 4 GB"])
        #expect(SizeBucket.allCases.map(\.id) == ["underOneGB", "oneToFourGB", "overFourGB"])
    }

    @Test func sizeFilterNarrowsTheSizesShownInTheDetail() {
        let sizes = family("f", variants: [entry("tiny", size: 500_000_000), entry("mid", size: 2_000_000_000), entry("huge", size: 6_000_000_000)])
        let filter = FamilyFilter(fitsOnly: false, sizes: [.underOneGB, .overFourGB])
        #expect(FamilyLogic.variants(of: sizes, filter: filter).map(\.id) == ["tiny", "huge"])
        #expect(FamilyLogic.apply([sizes], sort: .name, filter: FamilyFilter(fitsOnly: false, sizes: [.oneToFourGB])).count == 1)
        #expect(FamilyLogic.apply([sizes], sort: .name, filter: FamilyFilter(fitsOnly: false, sizes: [.underOneGB])).count == 1)
        let big = family("g", variants: [entry("g1", size: 6_000_000_000)])
        #expect(FamilyLogic.apply([big], sort: .name, filter: FamilyFilter(fitsOnly: false, sizes: [.underOneGB])).isEmpty)
    }

    @Test func detailRowsGoFromTheSmallestModelAndPutGGUFFirstAtTheSameSize() {
        let sizes = family("f", variants: [
            entry("e4b-mlx", source: .mlx, params: "E4B"), entry("e2b-mlx", source: .mlx, params: "E2B"),
            entry("e4b-gguf", source: .gguf, params: "E4B"), entry("e2b-gguf", source: .gguf, params: "E2B"),
            entry("same-a", source: .gguf, params: "E4B"),
        ])
        #expect(FamilyLogic.variants(of: sizes, filter: FamilyFilter(fitsOnly: false)).map(\.id)
            == ["e2b-gguf", "e2b-mlx", "e4b-gguf", "same-a", "e4b-mlx"])
    }
}
