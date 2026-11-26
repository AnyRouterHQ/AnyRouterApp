import Foundation

protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPFetching {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LocalModelError.invalidResponse }
        return (data, http)
    }
}

/// One file in a repo listing. `sha256` is the LFS oid, present for large files.
struct HFFile: Hashable, Sendable, Codable {
    var path: String
    var size: Int64
    var sha256: String?
}

struct HFSearchResult: Hashable, Sendable, Identifiable, Decodable {
    /// Repo id, `org/name`.
    var id: String
    var downloads: Int?
    var likes: Int?
    var pipelineTag: String?
    var tags: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, downloads, likes, tags
        case pipelineTag = "pipeline_tag"
    }
}

/// The few Hugging Face endpoints the app needs. Public data only: no token is sent.
struct HuggingFaceAPI: Sendable {
    var baseURL: URL
    var http: any HTTPFetching

    init(baseURL: URL = URL(string: "https://huggingface.co")!, http: any HTTPFetching = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    // MARK: Validation

    /// `org/name` with the characters Hugging Face allows. Also keeps `..` and extra slashes out of URLs and paths.
    static func isValidRepo(_ repo: String) -> Bool {
        repo.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
            && !repo.contains("..")
    }

    /// A relative path inside a repo: no leading slash, no `..`, no empty parts.
    static func isSafeFilePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != ".." && $0 != "." }
    }

    // MARK: URLs

    /// `/api/models?search=<query>&filter=<gguf|mlx>&pipeline_tag=text-generation&sort=downloads&direction=-1&limit=<n>`
    func searchURL(query: String, format: LocalModelFormat, limit: Int = 30) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/models"
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: trimmed)) }
        items += [
            URLQueryItem(name: "filter", value: format.rawValue),
            URLQueryItem(name: "pipeline_tag", value: "text-generation"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        components.queryItems = items
        return components.url!
    }

    /// `/api/models/<repo>/tree/<revision>?recursive=true`
    func treeURL(repo: String, revision: String = "main") -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/api/models/\(Self.encode(repo))/tree/\(Self.encode(revision))"
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        return components.url!
    }

    /// `/<repo>/resolve/<revision>/<path>`, the direct file download.
    func resolveURL(repo: String, revision: String = "main", path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/\(Self.encode(repo))/resolve/\(Self.encode(revision))/\(Self.encode(path))"
        return components.url!
    }

    private static func encode(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    // MARK: Requests

    func search(query: String, format: LocalModelFormat, limit: Int = 30) async throws -> [HFSearchResult] {
        let data = try await get(searchURL(query: query, format: format, limit: limit), what: "search")
        let results = try JSONDecoder().decode([HFSearchResult].self, from: data)
        return results.filter { Self.isValidRepo($0.id) }
    }

    /// Every file in the repo at `revision`. Directories are dropped, unsafe paths throw.
    func listFiles(repo: String, revision: String = "main") async throws -> [HFFile] {
        guard Self.isValidRepo(repo) else { throw LocalModelError.invalidRepo(repo) }
        let data = try await get(treeURL(repo: repo, revision: revision), what: repo)
        return try Self.decodeTree(data)
    }

    static func decodeTree(_ data: Data) throws -> [HFFile] {
        struct Item: Decodable {
            struct LFS: Decodable { var oid: String }
            var type: String
            var path: String
            var size: Int64?
            var lfs: LFS?
        }
        let items = try JSONDecoder().decode([Item].self, from: data)
        return try items.filter { $0.type == "file" }.map { item in
            guard isSafeFilePath(item.path) else { throw LocalModelError.invalidFilePath(item.path) }
            return HFFile(path: item.path, size: item.size ?? 0, sha256: item.lfs?.oid)
        }
    }

    private func get(_ url: URL, what: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await http.fetch(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw LocalModelError.gatedOrPrivate(what)
        case 404: throw LocalModelError.notFound(what)
        default: throw LocalModelError.http(status: response.statusCode)
        }
    }
}
