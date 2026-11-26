import Foundation

/// Where the shared catalog lives. Models are added with a pull request to these files, no app release needed.
enum CatalogSource {
    static let productionURL = URL(string: "https://raw.githubusercontent.com/AnyRouterHQ/AnyRouterApp/main/catalog/models.json")!
    static let developmentURL = URL(string: "https://raw.githubusercontent.com/AnyRouterHQ/AnyRouterApp/main/catalog/dev-models.json")!
}

/// What the user changed about the catalog: models they added, a custom catalog URL, and the dev catalog switch.
struct CatalogSettings: Codable, Equatable, Sendable {
    var userModels: [CatalogEntry] = []
    /// Replaces the default catalog URL when set.
    var remoteCatalogURL: URL?
    var useDevelopmentCatalog = false

    /// The catalog to fetch: the user's own URL, else the development or production file of the repo.
    var effectiveCatalogURL: URL {
        remoteCatalogURL ?? (useDevelopmentCatalog ? CatalogSource.developmentURL : CatalogSource.productionURL)
    }

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

extension CatalogSettings {
    /// Settings saved before a field existed still load: a missing key is the default, never a lost user model list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userModels = try c.decodeIfPresent([CatalogEntry].self, forKey: .userModels) ?? []
        remoteCatalogURL = try c.decodeIfPresent(URL.self, forKey: .remoteCatalogURL)
        useDevelopmentCatalog = try c.decodeIfPresent(Bool.self, forKey: .useDevelopmentCatalog) ?? false
    }
}
