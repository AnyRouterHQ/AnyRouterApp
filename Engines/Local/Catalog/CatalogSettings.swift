import Foundation

/// What the user changed about the catalog: models they added, and an optional remote catalog URL.
struct CatalogSettings: Codable, Equatable, Sendable {
    var userModels: [CatalogEntry] = []
    var remoteCatalogURL: URL?

    private static let defaultsKey = "local.catalogSettings"

    static func load(from defaults: UserDefaults = .standard) -> CatalogSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(CatalogSettings.self, from: data)
        else { return CatalogSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// Adds entries, replacing any with the same id.
    mutating func add(_ entries: [CatalogEntry]) {
        let ids = Set(entries.map(\.id))
        userModels.removeAll { ids.contains($0.id) }
        userModels.append(contentsOf: entries)
    }

    mutating func remove(id: String) {
        userModels.removeAll { $0.id == id }
    }

    /// Remote catalogs must be https: a plain-http catalog could be swapped in transit.
    static func isAcceptableRemoteCatalogURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }
}
