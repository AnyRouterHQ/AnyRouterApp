import Foundation
import Observation

/// What Settings › Skills does that is not a plain read or write: importing from a link with an approval step, syncing
/// from an AnyRouter hub, and the message a refused action leaves on the page (agent design 4.2, unit K2).
@MainActor
@Observable
final class SkillsModel {
    /// A parsed import waiting for the user's yes. Nothing is stored until `confirmImport`.
    struct PendingImport: Equatable {
        let draft: SkillDraft
        let ref: String
    }

    private(set) var pending: PendingImport?
    /// The reason the last action was refused, shown at the top of the page.
    private(set) var failure: String?
    /// What the last sync changed.
    private(set) var syncNote: String?
    private(set) var isWorking = false

    @ObservationIgnored private let importer: SkillImporter
    @ObservationIgnored private let hub: HubSkillsClient

    init(importer: SkillImporter = SkillImporter(), hub: HubSkillsClient = HubSkillsClient()) {
        self.importer = importer
        self.hub = hub
    }

    /// Fetches and parses the file at `text`, then waits for approval in `pending`.
    func importFromURL(_ text: String) async {
        failure = nil
        pending = nil
        do {
            let url = try SkillImportLogic.url(from: text)
            isWorking = true
            defer { isWorking = false }
            let draft = try SkillLibraryLogic.parse(try await importer.fetch(url))
            pending = PendingImport(draft: draft, ref: url.absoluteString)
        } catch {
            failure = error.localizedDescription
        }
    }

    func confirmImport(into store: SkillStore) {
        guard let approved = pending else { return }
        pending = nil
        perform { try store.add(approved.draft, source: .imported, sourceRef: approved.ref) }
    }

    func discardImport() { pending = nil }

    func sync(tokens: any TokenStoring, into store: SkillStore) async {
        failure = nil
        syncNote = nil
        isWorking = true
        defer { isWorking = false }
        do {
            syncNote = try store.sync(try await hub.sync(tokens: tokens)).summary
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Runs a write; a refusal shows at the top of the page.
    func perform(_ work: () throws -> Void) {
        failure = nil
        do { try work() } catch { failure = error.localizedDescription }
    }
}
