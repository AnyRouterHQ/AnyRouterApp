import Foundation
import Observation

/// Whether a local model is expected to run on this device.
enum ModelFit: Sendable, Equatable {
    case fits, tight, wontFit, unknown
}

enum DownloadState: Sendable, Equatable {
    case notInstalled
    /// `progress` is 0...1, or nil while the size is not known yet.
    case downloading(progress: Double?)
    case paused(progress: Double?)
    case verifying
    case installed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .downloading, .paused, .verifying: true
        default: false
        }
    }
}

/// A short label on a model card.
struct ModelBadge: Hashable, Sendable {
    enum Tone: String, Sendable { case neutral, info, success, warning }
    var label: String
    var tone: Tone = .neutral
}

/// Whether and how a model runs on this device, with the numbers behind it.
struct FitDetail: Hashable, Sendable {
    /// `.fits` runs well, `.tight` loads with a shorter context, `.wontFit` does not load.
    var verdict: ModelFit
    /// Memory to run the model entirely in RAM: weights, KV cache and runtime overhead.
    var neededBytes: Int64
    /// What this device can give a model.
    var budgetBytes: Int64
    /// Largest context that fits, in tokens.
    var context: Int
    var maxReply: Int
    /// Only the experts in use stay in RAM; the file is read from storage as needed.
    var streamsFromStorage: Bool
    /// The numbers come from a guess at the model's shape, not its metadata.
    var isEstimate: Bool
    /// The model has a vision projector and this device has room for it as well, so photos work.
    var acceptsImages = false
    /// Set when the model does not fit here but streams on a device with this much RAM, in GB.
    var streamsWithRAMGigabytes: Int? = nil
}

/// A local (GGUF or MLX) model shown in the hub and the onboarding picker.
struct LocalModelEntry: Identifiable, Hashable, Sendable {
    var descriptor: ModelDescriptor
    var summary: String
    var tags: [String]
    var fit: ModelFit
    /// Added by the user (custom repo), so it can be removed.
    var isUserAdded: Bool
    /// Why this model cannot run on this device (for example MLX in the Simulator). Nil when it can.
    var unavailableReason: String? = nil
    var badges: [ModelBadge] = []
    var fitDetail: FitDetail? = nil
    /// The catalog offers it first in onboarding.
    var isOnboarding = false
    /// The catalog marks it as a top pick.
    var isRecommended = false
    /// The family this size belongs to (Gemma 4, Qwen 3.5). Nil for a repo the user added.
    var familyID: String? = nil
    var familyName: String? = nil
    var publisher: String? = nil
    /// Short key for the family logo ("gemma", "qwen").
    var logo: String? = nil
    var website: String? = nil
    /// "4B", "E2B": what this size is called, and how big it is for sorting (0.7 for "700M").
    var parameters: String? = nil
    var parameterBillions: Double? = nil
    var quantization: String? = nil
    /// ISO date the size was added or last updated, for "Newest".
    var releasedAt: String? = nil
    /// Hidden from browsing and recommendations. Installed copies keep working and say what replaces them.
    var isDeprecated = false
    /// Name of the family that replaces a deprecated one.
    var replacementName: String? = nil
    /// Hugging Face repo (`org/name`), empty when unknown, and the commit or branch it downloads from. Nil revision means `main`.
    var repo = ""
    var revision: String? = nil
    var id: String { descriptor.id }
}

/// A model line at one generation with its sizes: what the model browser lists first.
struct LocalModelFamily: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var publisher: String
    var logo: String
    var summary: String
    var website: String?
    /// Catalog tags: "thinking", "vision", "audio", "tools", "code", "multilingual".
    var tags: [String]
    /// The catalog's own badges: "best", "recommended", "new".
    var badges: [String]
    /// Every size in every format, in catalog order.
    var variants: [LocalModelEntry]
}

/// A Hugging Face repo found by search. Its files become `LocalModelEntry` values on demand.
struct RepoHit: Identifiable, Hashable, Sendable {
    var repo: String
    var source: ModelSource
    var downloads: Int?
    var likes: Int?
    var id: String { "\(source.rawValue)/\(repo)" }
}

/// What the UI needs from the local model catalog and downloads. `LocalModelHub` conforms.
@MainActor
protocol ModelHubService: AnyObject {
    /// Curated, remote and user-added models, installed or not.
    var catalog: [LocalModelEntry] { get }
    var lastError: String? { get }
    var remoteCatalogURL: String { get }
    /// True while the shared catalog is read from `dev-models.json` instead of `models.json`.
    var usesDevelopmentCatalog: Bool { get }
    /// One line for Local Models when this install has the standard memory limit (the increased limit is not signed in),
    /// else nil. Sideloaded builds re-signed with a free Apple ID lose it.
    var memoryLimitNote: String? { get }

    /// Fetches the shared catalog (cached with an ETag) and reloads. Never throws: a failed fetch keeps the cached list.
    func refreshCatalog() async
    func setUsesDevelopmentCatalog(_ on: Bool) async
    /// Reloads the catalog and refreshes install state from disk.
    func reload() async
    func downloadState(for modelID: String) -> DownloadState
    func download(_ entry: LocalModelEntry)
    func pause(modelID: String)
    func resume(modelID: String)
    func cancel(modelID: String)
    func delete(modelID: String) async

    func searchRepos(_ query: String) async throws -> [RepoHit]
    func entries(for hit: RepoHit) async throws -> [LocalModelEntry]
    /// Adds every GGUF file (or the MLX snapshot) of a repo to the user's catalog.
    func addRepo(_ hit: RepoHit) async throws
    func removeUserModel(modelID: String) async
    /// Empty text clears the remote catalog.
    func setRemoteCatalogURL(_ text: String) async throws
}

extension ModelHubService {
    /// Deletes every installed model, one at a time. A model that fails to delete leaves `lastError` set and the rest still go.
    func deleteAllModels() async {
        for entry in catalog where downloadState(for: entry.id) == .installed {
            await delete(modelID: entry.id)
        }
    }

    /// Removes models from the person's own list (`removeUserModel`), one at a time.
    func removeUserModels(_ ids: [String]) async {
        for id in ids { await removeUserModel(modelID: id) }
    }

    /// Current model families with their sizes. Deprecated models are not listed.
    var families: [LocalModelFamily] { FamilyLogic.families(from: catalog) }
    /// Models without a family (repos the user added).
    var ungroupedModels: [LocalModelEntry] { FamilyLogic.ungrouped(catalog) }
}

/// Inert default for previews and tests.
@MainActor @Observable
final class EmptyModelHubService: ModelHubService {
    var catalog: [LocalModelEntry] = []
    var lastError: String?
    var remoteCatalogURL: String = ""
    var usesDevelopmentCatalog = false
    var memoryLimitNote: String?

    func refreshCatalog() async {}
    func setUsesDevelopmentCatalog(_ on: Bool) async { usesDevelopmentCatalog = on }
    func reload() async {}
    func downloadState(for modelID: String) -> DownloadState { .notInstalled }
    func download(_ entry: LocalModelEntry) {}
    func pause(modelID: String) {}
    func resume(modelID: String) {}
    func cancel(modelID: String) {}
    func delete(modelID: String) async {}
    func searchRepos(_ query: String) async throws -> [RepoHit] { [] }
    func entries(for hit: RepoHit) async throws -> [LocalModelEntry] { [] }
    func addRepo(_ hit: RepoHit) async throws {}
    func removeUserModel(modelID: String) async {}
    func setRemoteCatalogURL(_ text: String) async throws { remoteCatalogURL = text }
}
