import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct SkillsModelTests {
    private let file = "---\nname: bill-splitter\ndescription: Split a bill.\n---\n1. Ask who paid."
    private let markdown = ["Content-Type": "text/markdown"]

    private func store() throws -> SkillStore { SkillStore(context: ModelContext(try ModelContainer.anyRouter(inMemory: true))) }

    private func rig(_ handler: @escaping @Sendable (URLRequest) -> StubRegistry.Reply) -> (model: SkillsModel, link: String) {
        let api = StubbedAPI(handler)
        let model = SkillsModel(importer: SkillImporter(session: api.session), hub: HubSkillsClient(config: api.config, session: api.session))
        return (model, "https://\(api.host)/SKILL.md")
    }

    @Test func anImportWaitsForApprovalAndSavesNothingUntilThen() async throws {
        let body = file, headers = markdown
        let (model, link) = rig { _ in StubRegistry.Reply(body: Data(body.utf8), headers: headers) }
        let store = try store()
        await model.importFromURL("  \(link) ")
        #expect(model.failure == nil && !model.isWorking)
        let pending = try #require(model.pending)
        #expect(pending.draft == SkillDraft(name: "bill-splitter", description: "Split a bill.", body: "1. Ask who paid."))
        #expect(pending.ref == link)
        #expect(try store.all().isEmpty, "nothing is stored before the user says yes")

        model.confirmImport(into: store)
        #expect(model.pending == nil && model.failure == nil)
        let saved = try #require(try store.all().first)
        #expect(saved.name == "bill-splitter" && saved.source == .imported && saved.sourceRef == link && saved.enabled)
    }

    @Test func discardingAnImportStoresNothing() async throws {
        let body = file, headers = markdown
        let (model, link) = rig { _ in StubRegistry.Reply(body: Data(body.utf8), headers: headers) }
        let store = try store()
        await model.importFromURL(link)
        model.discardImport()
        model.confirmImport(into: store)
        #expect(model.pending == nil && model.failure == nil)
        #expect(try store.all().isEmpty)
    }

    @Test func aBadLinkOrFileLeavesAMessageAndNothingPending() async throws {
        let headers = markdown
        let (model, link) = rig { _ in StubRegistry.Reply(body: Data("# Just steps".utf8), headers: headers) }
        await model.importFromURL("http://example.com/SKILL.md")
        #expect(model.failure == SkillImportError.notHTTPS.errorDescription && model.pending == nil)
        await model.importFromURL(link)
        #expect(model.failure == SkillIssue.noFrontMatter.errorDescription && model.pending == nil && !model.isWorking)
    }

    @Test func approvingAnImportThatClashesShowsTheReason() async throws {
        let body = file, headers = markdown
        let (model, link) = rig { _ in StubRegistry.Reply(body: Data(body.utf8), headers: headers) }
        let store = try store()
        try store.add(SkillDraft(name: "bill-splitter", description: "Mine.", body: "1. Mine."), source: .proposed)
        await model.importFromURL(link)
        model.confirmImport(into: store)
        #expect(model.failure == SkillStoreError.duplicate("bill-splitter").errorDescription)
        #expect(try store.all().count == 1)
    }

    @Test func aSyncStoresTheHubSkillsAndSaysWhatChanged() async throws {
        let hub = #"{"hubs":[{"slug":"mine","items":[{"slug":"alpha","kind":"skill","description":"A.","body":"1. a"}]}]}"#
        let (model, _) = rig { _ in StubRegistry.Reply(body: Data(hub.utf8)) }
        let store = try store()
        await model.sync(tokens: FakeTokens("key-1"), into: store)
        #expect(model.syncNote == "1 added." && model.failure == nil && !model.isWorking)
        #expect(try store.all().map(\.name) == ["alpha"])
        await model.sync(tokens: FakeTokens("key-1"), into: store)
        #expect(model.syncNote == "Nothing changed.")
    }

    @Test func aRefusedSyncShowsTheMessageAndKeepsWhatWasStored() async throws {
        let (model, _) = rig { _ in StubRegistry.Reply(status: 403) }
        let store = try store()
        try store.add(SkillDraft(name: "alpha", description: "A.", body: "1. a"), source: .hub, sourceRef: "mine/alpha")
        await model.sync(tokens: FakeTokens("key-1"), into: store)
        #expect(model.failure == HubSkillsClient.refusedText && model.syncNote == nil && !model.isWorking)
        #expect(try store.all().count == 1, "a failed sync deletes nothing")
    }

    @Test func aWriteThatIsRefusedShowsItsReasonAndTheNextOneClearsIt() throws {
        let model = SkillsModel()
        model.perform { throw SkillStoreError.full(100) }
        #expect(model.failure == SkillStoreError.full(100).errorDescription)
        model.perform {}
        #expect(model.failure == nil)
    }
}
