import Foundation

/// One skill from one of the signed-in user's AnyRouter hubs. The text is untrusted: `SkillStore` checks it and caps it
/// before anything is saved.
struct HubSkillItem: Equatable, Sendable {
    let hub: String
    let slug: String
    let description: String?
    let body: String

    /// Names the item across syncs: `<hub slug>/<item slug>`.
    var ref: String { "\(hub)/\(slug)" }
}

/// `GET /hubs/sync`: the skills in the signed-in user's hubs (agent design 4.2, unit K2).
///
/// The response shape is not in AnyRouter's published docs or OpenAPI file. It is read from the `anyr` command line tool,
/// which calls the same endpoint: `{ "hubs": [{ "slug", "items": [{ "slug", "kind", "description", "body",
/// "security_scan_status" }] }] }`. The parser keeps the items of kind `skill` that the hub's scan did not flag and ignores
/// every other field, so extra fields do not break it.
struct HubSkillsClient: Sendable {
    var config: AnyRouterConfig = .standard
    var session: URLSession = .shared

    static let refusedText = "AnyRouter did not accept this sign-in for hub sync. Syncing skills may need a Pro or Max plan."

    /// Reads the key from `tokens` and sends it as the app's other AnyRouter calls do. A refusal is an error to show: unlike
    /// a chat, it never clears the key or signs the user out.
    func sync(tokens: any TokenStoring) async throws -> [HubSkillItem] {
        guard let key = tokens.token() else { throw AnyRouterError.signedOut }
        var request = URLRequest(url: config.baseURL.appending(path: "hubs/sync"), timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        AnyRouterEngine(tokens: tokens, config: config, session: session).applyHeaders(&request, key: key)
        let (data, response) = try await session.data(for: request)
        let status = AnyRouterError.status(of: response)
        guard (200..<300).contains(status) else {
            let refused = status == 401 || status == 403
            throw AnyRouterError.http(status: status, message: refused ? Self.refusedText : AnyRouterError.message(from: data, status: status))
        }
        return try Self.parse(data)
    }

    /// A body with no `hubs` list is a failure, not an empty answer: an empty list would delete every synced skill.
    static func parse(_ data: Data) throws -> [HubSkillItem] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), let hubs = root["hubs"]?.array else {
            throw AnyRouterError.badResponse
        }
        return hubs.flatMap { hub -> [HubSkillItem] in
            guard let hubSlug = hub["slug"]?.string else { return [] }
            return (hub["items"]?.array ?? []).compactMap { item -> HubSkillItem? in
                guard item["kind"]?.string == "skill", item["security_scan_status"]?.string != "flagged",
                      let slug = item["slug"]?.string, let body = item["body"]?.string else { return nil }
                return HubSkillItem(hub: hubSlug, slug: slug, description: item["description"]?.string, body: body)
            }
        }
    }
}
