import Foundation

/// Reads one web page as text. https only, no local network, capped in time and size.
struct FetchURLTool: BuiltInTool {
    static let toolName = "fetch_url"
    let name = FetchURLTool.toolName
    let title = "Read a web page"
    let summary = "Fetch a page and read its text (https only)"
    let description = "Fetch a web page over https and return its readable text. Use it to read a link the user gave you or a search result."
    let schema: JSONSchema = #"{"type":"object","properties":{"url":{"type":"string","description":"The https URL to read"}},"required":["url"]}"#
    let needsNetwork = true

    var session: URLSession = .shared
    var timeout: TimeInterval = 15
    var maxBytes = 1_000_000
    var maxCharacters = 12_000

    func run(_ arguments: JSONValue) async throws -> String {
        guard let text = arguments["url"]?.string, !text.isEmpty else { throw BuiltInToolError("Missing the \"url\" argument.") }
        let url: URL
        switch FetchURLPolicy.validate(text) {
        case .success(let value): url = value
        case .failure(let problem): throw BuiltInToolError(problem.message)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html, text/plain, application/json;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("AnyRouter for iOS", forHTTPHeaderField: "User-Agent")

        let fetched: (URLSession.AsyncBytes, URLResponse)
        do {
            fetched = try await session.bytes(for: request, delegate: RedirectGuard())
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw BuiltInToolError("Could not load the page: \(error.localizedDescription)")
        }
        let (bytes, response) = fetched
        guard let http = response as? HTTPURLResponse else { throw BuiltInToolError("Not an HTTP answer.") }
        guard (200..<300).contains(http.statusCode) else { throw BuiltInToolError("The page answered HTTP \(http.statusCode).") }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard type.isEmpty || type.contains("text/") || type.contains("json") || type.contains("xml") else {
            throw BuiltInToolError("Cannot read this content type: \(type).")
        }

        var data = Data()
        var truncated = false
        try await bytes.forEachChunk { chunk in
            data.append(chunk)
            guard data.count >= maxBytes else { return true }
            data = data.prefix(maxBytes)
            truncated = true
            return false
        }
        let body = String(decoding: data, as: UTF8.self)
        let isHTML = type.contains("html") || (type.isEmpty && body.lowercased().contains("<html"))
        let readable = isHTML ? HTMLText.readable(body) : body
        var out = "URL: \(http.url?.absoluteString ?? url.absoluteString)\n"
        if isHTML, let title = HTMLText.title(in: body) { out += "Title: \(title)\n" }
        out += "\n" + clippedText(readable, limit: maxCharacters)
        if truncated { out += "\n[The page was larger than \(maxBytes / 1000) KB; the rest was not read.]" }
        return out
    }

    /// Refuses a redirect to a URL the policy would not allow (http, the local network).
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let target = request.url, case .success = FetchURLPolicy.validate(target.absoluteString) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}

enum FetchURLPolicy {
    struct Problem: Error, Equatable {
        let message: String
    }

    static func validate(_ text: String) -> Result<URL, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(), !host.isEmpty else {
            return .failure(Problem(message: "That is not a valid URL."))
        }
        guard scheme == "https" else { return .failure(Problem(message: "Only https URLs can be read.")) }
        guard !isLocal(host: host) else { return .failure(Problem(message: "Addresses on this device or its network cannot be read.")) }
        return .success(url)
    }

    /// Localhost, `.local`/`.internal` names, private and link-local IPv4 in any spelling (`127.1`, `0x7f.0.0.1`,
    /// `2130706433`), and loopback, private, link-local or IPv4-mapped IPv6. An address it cannot read is refused.
    static func isLocal(host raw: String) -> Bool {
        var host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }
        if host.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { return true }
            let bytes = withUnsafeBytes(of: &address) { Array($0) }
            if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 { return true } // :: and ::1
            if bytes[0] & 0xFE == 0xFC { return true } // fc00::/7
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true } // fe80::/10
            return bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF // ::ffff:0:0/96
        }
        // Only digits, dots and hex marks can be an IPv4 address; inet_aton reads the same short, octal and hex
        // spellings the system resolver does.
        guard host.range(of: "^[0-9a-fx.]+$", options: .regularExpression) != nil else { return false }
        var address = in_addr()
        guard inet_aton(host, &address) != 0 else { return false }
        let ip = UInt32(bigEndian: address.s_addr)
        switch (Int(ip >> 24), Int((ip >> 16) & 0xFF)) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }
}
