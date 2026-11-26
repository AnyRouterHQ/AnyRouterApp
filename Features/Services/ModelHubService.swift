import Foundation
import Observation

/// Whether a local model is expected to run on this device.
enum ModelFit: Sendable, Equatable {
    case fits, tight, wontFit, unknown
}

enum DownloadState: Sendable, Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installed
    case failed(String)
}

/// A local (GGUF or MLX) model shown in the hub and the onboarding picker.
struct LocalModelEntry: Identifiable, Hashable, Sendable {
    var descriptor: ModelDescriptor
    var summary: String
    var tags: [String]
    var fit: ModelFit
    var id: String { descriptor.id }
}

/// What the UI needs from local model catalog and downloads. Lane C conforms (`@MainActor @Observable` class).
@MainActor
protocol ModelHubService: AnyObject {
    /// Curated plus user-added models, installed or not.
    var catalog: [LocalModelEntry] { get }
    func downloadState(for modelID: String) -> DownloadState
    func search(_ query: String) async throws -> [LocalModelEntry]
    func download(_ entry: LocalModelEntry)
    func cancelDownload(modelID: String)
    func delete(modelID: String) async
    /// Extra Hugging Face repos the user added to the catalog.
    var customRepos: [String] { get }
    func addRepo(_ repo: String)
    func removeRepo(_ repo: String)
    var remoteCatalogURL: String { get set }
}

/// Default until the local engine lane provides the real service.
@MainActor @Observable
final class EmptyModelHubService: ModelHubService {
    var catalog: [LocalModelEntry] { [] }
    var customRepos: [String] = []
    var remoteCatalogURL: String = ""

    func downloadState(for modelID: String) -> DownloadState { .notInstalled }
    func search(_ query: String) async throws -> [LocalModelEntry] { [] }
    func download(_ entry: LocalModelEntry) {}
    func cancelDownload(modelID: String) {}
    func delete(modelID: String) async {}
    func addRepo(_ repo: String) { if !customRepos.contains(repo) { customRepos.append(repo) } }
    func removeRepo(_ repo: String) { customRepos.removeAll { $0 == repo } }
}
