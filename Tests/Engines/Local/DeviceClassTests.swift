import Foundation
import Testing
@testable import AnyRouter

struct DeviceClassTests {
    private func verdict(_ model: CatalogEntry, _ deviceClass: DeviceClass, _ kind: MemoryLimitKind) throws -> FitEstimate.Verdict {
        FitPlanner.estimate(try #require(model.memoryProfile), memory: deviceClass.memory(kind)).verdict
    }

    private func model(_ repoPart: String, params: String, engine: LocalModelFormat = .gguf) throws -> CatalogEntry {
        try #require(BundledCatalog.load().models.first {
            $0.repo.contains(repoPart) && $0.parameters == params && $0.format == engine
        }, "the catalog has no \(repoPart) \(params)")
    }

    // MARK: Table

    @Test func eachClassHasAStandardAndAnIncreasedBudgetThatGrowWithRAM() {
        var lastStandard: Int64 = 0
        var lastIncreased: Int64 = 0
        for deviceClass in DeviceClass.allCases {
            let standard = deviceClass.memory(.standard).budgetBytes
            let increased = deviceClass.memory(.increased).budgetBytes
            #expect(increased > standard, "\(deviceClass.rawValue) GB: the entitlement must help")
            #expect(standard >= lastStandard && increased > lastIncreased)
            #expect(standard == deviceClass.limitBytes(.standard) - DeviceMemory.appBaselineBytes)
            #expect(deviceClass.memory(.increased).physicalBytes == Int64(deviceClass.rawValue) * 1_000_000_000)
            #expect(!deviceClass.examples.isEmpty)
            (lastStandard, lastIncreased) = (standard, increased)
        }
    }

    @Test func theBudgetsAreTheDocumentedOnes() {
        let expected: [DeviceClass: (standard: Int64, increased: Int64)] = [
            .gb4: (1_500_000_000, 2_500_000_000), .gb6: (2_500_000_000, 3_900_000_000), .gb8: (3_100_000_000, 5_300_000_000),
            .gb12: (3_200_000_000, 8_100_000_000), .gb16: (4_200_000_000, 10_900_000_000),
        ]
        for (deviceClass, budgets) in expected {
            #expect(deviceClass.memory(.standard).budgetBytes == budgets.standard, "\(deviceClass) standard")
            #expect(deviceClass.memory(.increased).budgetBytes == budgets.increased, "\(deviceClass) increased")
        }
    }

    @Test func theRAMTheSystemReportsMapsToTheNominalClass() {
        #expect(DeviceClass.nearest(physicalBytes: 3_700_000_000) == .gb4)
        #expect(DeviceClass.nearest(physicalBytes: 5_700_000_000) == .gb6)
        #expect(DeviceClass.nearest(physicalBytes: 7_500_000_000) == .gb8)
        #expect(DeviceClass.nearest(physicalBytes: 11_300_000_000) == .gb12)
        #expect(DeviceClass.nearest(physicalBytes: 15_000_000_000) == .gb16)
        #expect(DeviceClass.nearest(physicalBytes: 0) == .gb4)
        #expect(DeviceClass.nearest(physicalBytes: 64_000_000_000) == .gb16)
    }

    // MARK: The catalog on each class

    @Test func gemma4E2BRunsWellOnA6GBPhoneAndE4BNeedsMore() throws {
        let e2b = try model("gemma-4-E2B", params: "E2B")
        let e4b = try model("gemma-4-E4B", params: "E4B")
        #expect(try verdict(e2b, .gb6, .increased) == .runsWell)
        #expect(try verdict(e4b, .gb6, .increased) != .runsWell, "E4B is tight or too big on a 6 GB phone")
        #expect(try verdict(e4b, .gb8, .increased) == .runsWell)
        #expect(try verdict(e4b, .gb12, .increased) == .runsWell)
        #expect(try verdict(e4b, .gb16, .increased) == .runsWell)
    }

    @Test func aSideloadedInstallStillRunsGemma4E2BFrom8GBUpAndLoadsItOn6GB() throws {
        let e2b = try model("gemma-4-E2B", params: "E2B")
        for deviceClass in [DeviceClass.gb8, .gb12, .gb16] { #expect(try verdict(e2b, deviceClass, .standard) == .runsWell) }
        guard case .tight = try verdict(e2b, .gb6, .standard) else {
            Issue.record("E2B should load, with limits, on a 6 GB phone with the standard limit")
            return
        }
    }

    @Test func aFourGigabyteDeviceRunsOnlyTheSmallestModels() throws {
        #expect(try verdict(model("Qwen3.5-0.8B", params: "0.8B"), .gb4, .increased) == .runsWell)
        #expect(try verdict(model("gemma-4-E2B", params: "E2B"), .gb4, .increased) != .runsWell)
        #expect(try verdict(model("Qwen3.5-4B", params: "4B"), .gb4, .increased) == .wontFit)
    }

    @Test func everyClassFrom4GBUpHasSomethingThatRunsWellWithTheIncreasedLimit() throws {
        let current = try BundledCatalog.load().models.filter { $0.status == .current }
        for deviceClass in DeviceClass.allCases {
            let well = current.filter { (try? verdict($0, deviceClass, .increased)) == .runsWell }
            #expect(!well.isEmpty, "\(deviceClass.rawValue) GB phones would see no recommendation")
        }
        for deviceClass in [DeviceClass.gb6, .gb8, .gb12, .gb16] {
            let well = current.filter { (try? verdict($0, deviceClass, .standard)) == .runsWell }
            #expect(!well.isEmpty, "\(deviceClass.rawValue) GB sideloaded installs would see no recommendation")
        }
    }

    @Test func aBiggerClassNeverRunsWorseThanASmallerOneForTheSameModel() throws {
        func rank(_ verdict: FitEstimate.Verdict) -> Int {
            switch verdict {
            case .wontFit: 0
            case .tight, .streamed: 1
            case .runsWell: 2
            }
        }
        for model in try BundledCatalog.load().models {
            for kind in MemoryLimitKind.allCases {
                var last = 0
                for deviceClass in DeviceClass.allCases {
                    let now = rank(try verdict(model, deviceClass, kind))
                    #expect(now >= last, "\(model.id) is worse on \(deviceClass.rawValue) GB than on a smaller class")
                    last = now
                }
            }
        }
    }

    @Test func aFamilyTaggedMobileHasASizeThatRunsWellOnA6GBPhone() throws {
        let document = try BundledCatalog.load()
        let mobile = document.families.filter { $0.status == .current && $0.tags.contains("mobile") }
        #expect(!mobile.isEmpty)
        for family in mobile {
            let well = document.models.filter { $0.familyID == family.id }.contains {
                (try? verdict($0, .gb6, .increased)) == .runsWell
            }
            #expect(well, "\(family.id) is tagged mobile but nothing of it runs well on a 6 GB phone")
        }
        for family in document.families where family.status == .current && !family.tags.contains("mobile") {
            let well = document.models.filter { $0.familyID == family.id }.contains {
                (try? verdict($0, .gb6, .increased)) == .runsWell
            }
            #expect(!well, "\(family.id) runs well on a 6 GB phone: tag it mobile")
        }
    }

    @Test func oldGenerationsAreHiddenAndPointToAReplacement() throws {
        let document = try BundledCatalog.load()
        let hidden = Set(document.families.filter { $0.status == .deprecated }.map(\.id))
        #expect(hidden.isSuperset(of: ["gemma-3", "llama-3-2", "qwen-3"]))
        let current = Set(document.families.filter { $0.status == .current }.map(\.id))
        for family in document.families where family.status == .deprecated {
            #expect(family.replacedBy.map(current.contains) == true, "\(family.id) must be replaced by a current family")
        }
    }
}
