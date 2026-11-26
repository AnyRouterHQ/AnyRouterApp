import Foundation
import Testing
@testable import AnyRouter

private func shortWire(_ place: Int) -> String { String(format: "vendor/m%02d", place) }
private func shortName(_ place: Int) -> String { String(format: "M%02d", place) }

/// The AnyRouter tab without a search: routers, the top ten of the week, the model in use, and a way to see the rest.
struct CloudShortListTests {
    private let models: [ModelDescriptor] = [
        cloudModel("anyrouter/auto", name: "AnyRouter Auto"), cloudModel("anyrouter/free", name: "AnyRouter Free"),
        cloudModel("anyrouter/byok", name: "AnyRouter BYOK"),
    ] + (0..<14).map { cloudModel(shortWire($0), name: shortName($0)) }

    /// M13 is the most used, M00 the least: the usage order is the opposite of the name order.
    private let rank: [String: Int] = Dictionary(uniqueKeysWithValues: (0..<14).map { (shortWire($0), 13 - $0) })

    private func list(
        query: String = "", rank: [String: Int]? = nil, short: Bool = true, currentID: String? = nil,
        prefs: CloudModelPrefs = CloudModelPrefs(), extra: [ModelDescriptor] = []
    ) -> CloudList {
        CloudListLogic.arrange(
            models: models + extra, query: query, sort: .topUsage, usageRank: rank ?? self.rank, showUnusable: true,
            prefs: prefs, currentID: currentID, short: short)
    }

    @Test func withoutASearchItIsTheRoutersAndExactlyTheTopTenInUsageOrder() {
        let short = list()
        #expect(short.isShort)
        #expect(short.routers.map(\.displayName) == ["AnyRouter Auto", "AnyRouter Free"], "BYOK stays out")
        #expect(short.rest.map(\.displayName) == (4...13).reversed().map(shortName))
        #expect(short.rest.count == CloudListLogic.topCount)
        #expect(short.moreCount == 4)
        #expect(short.current == nil)
        #expect(short.topPicks.isEmpty)
    }

    @Test func theTopTenAreNumberedOneToTen() {
        let usage = Dictionary(uniqueKeysWithValues: rank.map { ($0.key, ModelUsage(id: $0.key, rank: 14 - $0.value, tokens: 5000, requests: 9)) })
        let rows = list().rest.map { PickerRow.make($0, usage: CloudListLogic.rowUsage(of: $0, sort: .topUsage, in: usage)) }
        #expect(rows.compactMap(\.rankText) == (1...10).map { "#\($0)" })
    }

    @Test func aSearchLooksThroughTheWholeCatalogNotJustTheTopTen() {
        let one = list(query: "M03")
        #expect(!one.isShort)
        #expect(one.rest.map(\.displayName) == ["M03"], "M03 is outside the top ten")
        #expect(one.routers.isEmpty && one.current == nil && one.moreCount == 0)
        let many = list(query: "m0").rest.map(\.displayName)
        #expect(many.count == 10)
        #expect(many.contains("M00") && many.contains("M09"))
    }

    @Test func theModelInUseStaysVisibleEvenOutsideTheTopTen() {
        let outside = list(currentID: "anyrouter/" + shortWire(1))
        #expect(outside.current?.displayName == "M01")
        #expect(outside.moreCount == 3, "the current model is not counted as more")
        #expect(!outside.rest.contains { $0.displayName == "M01" })
        #expect(!outside.isEmpty)
    }

    @Test func aCurrentModelAlreadyOnTheListIsNotShownTwice() {
        #expect(list(currentID: "anyrouter/" + shortWire(13)).current == nil)
        #expect(list(currentID: ModelDescriptor.autoRouterID).current == nil)
        #expect(list(currentID: "anyrouter/" + shortWire(13)).moreCount == 4)
    }

    @Test func aCurrentModelThatCannotBeUsedOrIsNotFromAnyRouterIsLeftOut() {
        let locked = cloudModel("vendor/locked", name: "Locked", availability: .needsKey)
        #expect(list(currentID: locked.id, extra: [locked]).current == nil)
        let local = localModel("gguf/o/m/m.gguf")
        #expect(list(currentID: local.id, extra: [local]).current == nil)
        #expect(list(currentID: "anyrouter/gone/model").current == nil)
    }

    @Test func beforeAnyUsageIsKnownTheTopTenFollowTheChosenOrder() {
        let offline = list(rank: [:])
        #expect(offline.rest.map(\.displayName) == (0...9).map(shortName))
        #expect(offline.moreCount == 4)
    }

    @Test func aStarredModelLeavesTheTopSectionAndTheRoutersListKeepsTheOthers() {
        var prefs = CloudModelPrefs()
        prefs.toggleStar(shortWire(13))
        prefs.toggleStar("anyrouter/auto")
        let short = list(prefs: prefs)
        #expect(short.starred.map(\.displayName) == ["M13", "AnyRouter Auto"])
        #expect(short.rest.map(\.displayName) == (4...12).reversed().map(shortName))
        #expect(short.routers.map(\.displayName) == ["AnyRouter Free"])
        #expect(short.moreCount == 4)
    }

    @Test func leavingTheShortViewListsEveryModelInTheChosenOrder() {
        let full = list(short: false)
        #expect(!full.isShort)
        #expect(full.routers.isEmpty && full.current == nil && full.moreCount == 0)
        #expect(full.rest.count == 16)
        #expect(full.rest.map(\.displayName).prefix(4) == ["AnyRouter Auto", "AnyRouter Free", "M13", "M12"])
    }

    @Test func aListWithOnlyRoutersOrOnlyACurrentModelIsNotEmpty() {
        #expect(!CloudList(topPicks: [], rest: [], routers: [models[0]]).isEmpty)
        #expect(!CloudList(topPicks: [], rest: [], current: models[3]).isEmpty)
        #expect(CloudList(topPicks: [], rest: []).isEmpty)
    }
}
