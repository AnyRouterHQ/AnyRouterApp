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

    /// Merged catalog: bundled file, then the cached remote copy, then the user's models. Entries for other platforms
    /// are dropped. Throws only when the bundled file is broken; a bad cached remote copy is ignored.
    func entries() throws -> [CatalogEntry] {
        let current = settings()
        let remote = cachedRemote(for: current.effectiveCatalogURL) ?? []
        let merged = CatalogMerger.merge(bundled: try bundled().models, remote: remote, user: current.userModels)
        return merged.filter { $0.origin == .user || $0.isAvailableOnThisPlatform }
    }

    /// Fetches the catalog (the user's URL, else the development or production file) and caches it. Sends the stored
    /// ETag, so an unchanged file costs one small 304. Returns true when a new copy was stored.
    /// The document is decoded before it is cached, so a bad response never replaces a good copy.
    @discardableResult
    func refreshRemote() async throws -> Bool {
        let url = settings().effectiveCatalogURL
        guard CatalogSettings.isAcceptableRemoteCatalogURL(url) else { throw URLError(.unsupportedURL) }
        let cached = cacheFile(for: url)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        // An ETag without its body is useless, so only send it while the cached body is there.
        if FileManager.default.fileExists(atPath: cached.path), let etag = try? String(contentsOf: etagFile(for: url), encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await api.http.fetch(request)
        if response.statusCode == 304 { return false }
        guard (200..<300).contains(response.statusCode) else { throw LocalModelError.http(status: response.statusCode) }
        _ = try CatalogDocument.decode(data)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cached, options: .atomic)
        if let etag = response.value(forHTTPHeaderField: "ETag") {
            try etag.write(to: etagFile(for: url), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: etagFile(for: url))
        }
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

    private func etagFile(for url: URL) -> URL {
        cacheFile(for: url).deletingPathExtension().appendingPathExtension("etag")
    }

    private func cachedRemote(for url: URL) -> [CatalogEntry]? {
        guard let data = try? Data(contentsOf: cacheFile(for: url)) else { return nil }
        return try? CatalogDocument.decode(data).models
    }
}
