import Foundation

protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The first `maxBytes` of the body. Reads no more than that, even from a server that ignores the Range header.
    func fetchPrefix(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse)
}

extension HTTPFetching {
    /// For fakes: fetch, then cut. `URLSession` streams and stops instead.
    func fetchPrefix(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        var ranged = request
        ranged.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        let (data, response) = try await fetch(ranged)
        return (data.prefix(maxBytes), response)
    }
}

extension URLSession: HTTPFetching {
    /// Reads the body in the delegate's chunks and cancels the transfer once `maxBytes` are in, so a server that ignores
    /// the Range header cannot make the app download a whole model to read its header.
    func fetchPrefix(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        var ranged = request
        ranged.setValue("bytes=0-\(max(0, maxBytes - 1))", forHTTPHeaderField: "Range")
        return try await PrefixCollector(maxBytes: maxBytes).run(ranged, configuration: configuration)
    }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LocalModelError.invalidResponse }
        return (data, http)
    }
}

/// Collects the first bytes of one response with a data task of its own, then stops the transfer.
private final class PrefixCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var notHTTP = false
    private var capped = false
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                lock.withLock {
                    self.continuation = continuation
                    self.task = task
                }
                task.resume()
                session.finishTasksAndInvalidate()
            }
        } onCancel: {
            lock.withLock { task }?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.withLock {
            if let http = response as? HTTPURLResponse { self.response = http } else { notHTTP = true }
        }
        completionHandler(notHTTP ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let reachedCap = lock.withLock { () -> Bool in
            data.append(chunk)
            guard data.count >= maxBytes else { return false }
            data = data.prefix(maxBytes)
            capped = true
            return true
        }
        if reachedCap { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (waiting, outcome): (CheckedContinuation<(Data, HTTPURLResponse), Error>?, Result<(Data, HTTPURLResponse), Error>) =
            lock.withLock {
                defer { self.continuation = nil }
                if notHTTP { return (self.continuation, .failure(LocalModelError.invalidResponse)) }
                if let response, error == nil || capped { return (self.continuation, .success((data, response))) }
                return (self.continuation, .failure(error ?? LocalModelError.invalidResponse))
            }
        waiting?.resume(with: outcome)
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
        // The listing is paginated: follow the Link header until there is no next page, with a cap against loops.
        var files: [HFFile] = []
        var next: URL? = treeURL(repo: repo, revision: revision)
        var pages = 0
        while let url = next, pages < Self.maxListingPages {
            let (data, response) = try await getPage(url, what: repo)
            files += try Self.decodeTree(data)
            next = Self.nextPage(inLinkHeader: response.value(forHTTPHeaderField: "Link"), base: baseURL)
            pages += 1
        }
        if next != nil { throw LocalModelError.http(status: 508) }
        return files
    }

    /// A repo with more than this many pages of files (1,000 each) is not a model repo.
    static let maxListingPages = 40

    /// The `rel="next"` URL of an RFC 8288 `Link` header, only when it stays on the API host.
    static func nextPage(inLinkHeader header: String?, base: URL) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == #"rel="next""# }),
                  let first = pieces.first, first.hasPrefix("<"), first.hasSuffix(">"),
                  let url = URL(string: String(first.dropFirst().dropLast())),
                  url.scheme == base.scheme, url.host == base.host, url.path.hasPrefix("/api/models/")
            else { continue }
            return url
        }
        return nil
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

    /// What the fit check needs from a GGUF file, read from the start of the file on the Hub. Downloads the header only
    /// (a few MB, tens of MB with a large vocabulary), never the weights.
    func ggufInfo(repo: String, file: String, revision: String = "main") async throws -> GGUFInfo {
        guard Self.isValidRepo(repo) else { throw LocalModelError.invalidRepo(repo) }
        guard Self.isSafeFilePath(file) else { throw LocalModelError.invalidFilePath(file) }
        let url = resolveURL(repo: repo, revision: revision, path: file)
        return try await GGUFHeader.read { size in
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (data, response) = try await http.fetchPrefix(request, maxBytes: size)
            switch response.statusCode {
            case 200..<300: return data
            case 401, 403: throw LocalModelError.gatedOrPrivate(repo)
            case 404: throw LocalModelError.notFound(repo)
            default: throw LocalModelError.http(status: response.statusCode)
            }
        }
    }

    private func get(_ url: URL, what: String) async throws -> Data {
        try await getPage(url, what: what).0
    }

    private func getPage(_ url: URL, what: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await http.fetch(request)
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401, 403: throw LocalModelError.gatedOrPrivate(what)
        case 404: throw LocalModelError.notFound(what)
        default: throw LocalModelError.http(status: response.statusCode)
        }
    }
}
