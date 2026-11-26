import CryptoKit
import Foundation

/// The catalog the Hub shows: bundled models, the optional remote catalog (cached on disk), and the user's own repos,
/// merged by `CatalogMerger`. Also Hugging Face search and "add a repo".
actor CatalogService {
    private let bundled: @Sendable () throws -> CatalogDocument
    private let api: HuggingFaceAPI
    private let cacheDirectory: URL
    private let settings: @Sendable () -> CatalogSettings

    init(
        bundled: @escaping @Sendable () throws -> CatalogDocument = { try BundledCatalog.load() },
        api: HuggingFaceAPI = HuggingFaceAPI(),
        cacheDirectory: URL = URL.applicationSupportDirectory.appending(path: "Catalog", directoryHint: .isDirectory),
        settings: @escaping @Sendable () -> CatalogSettings = { CatalogSettings.load() }
    ) {
        self.bundled = bundled
        self.api = api
        self.cacheDirectory = cacheDirectory
        self.settings = settings
    }

    /// Merged catalog. Throws only when the bundled file is broken; a bad cached remote copy is ignored.
    func entries() throws -> [CatalogEntry] {
        let current = settings()
        let remote = current.remoteCatalogURL.flatMap { cachedRemote(for: $0) } ?? []
        return CatalogMerger.merge(bundled: try bundled().models, remote: remote, user: current.userModels)
    }

    /// Fetches the remote catalog from settings and caches it. Returns false when no URL is set.
    /// The document is decoded before it is cached, so a bad response never replaces a good copy.
    @discardableResult
    func refreshRemote() async throws -> Bool {
        guard let url = settings().remoteCatalogURL else { return false }
        guard CatalogSettings.isAcceptableRemoteCatalogURL(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await api.http.fetch(request)
        guard (200..<300).contains(response.statusCode) else { throw LocalModelError.http(status: response.statusCode) }
        _ = try CatalogDocument.decode(data)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheFile(for: url), options: .atomic)
        return true
    }

    func search(query: String, format: LocalModelFormat) async throws -> [HFSearchResult] {
        try await api.search(query: query, format: format)
    }

    /// Entries for a repo the user wants to add: one per GGUF file, or the MLX snapshot.
    func entries(forRepo repo: String, format: LocalModelFormat) async throws -> [CatalogEntry] {
        let files = try await api.listFiles(repo: repo)
        return try RepoFiles.entries(repo: repo, format: format, files: files)
    }

    // MARK: Cache

    /// One cache file per URL, so changing the URL never shows the old catalog.
    func cacheFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: "remote-\(name).json")
    }

    private func cachedRemote(for url: URL) -> [CatalogEntry]? {
        guard let data = try? Data(contentsOf: cacheFile(for: url)) else { return nil }
        return try? CatalogDocument.decode(data).models
    }
}
