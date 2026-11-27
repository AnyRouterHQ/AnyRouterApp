import Foundation

/// Which logo a model shows. Pure, so the mapping is tested without a view.
///
/// Slugs follow the AnyRouter web app (provider aliases and model families), so both apps agree.
/// A logo URL from the API wins. The bundled monochrome set is the fallback, then a symbol tile for a family that
/// has no public mark (`symbols` in the table), then a letter monogram (an owner without a public mark), then a
/// generic symbol.
enum ModelBrand: Equatable {
    /// A bundled template image in the asset catalog.
    case asset(String)
    /// A logo served by the API.
    case remote(URL)
    case symbol(String)
    /// An SF Symbol on a neutral rounded tile: a model family with no public mark.
    case tile(String)

    static let anyRouterMark = "BrandMark"
    static let unknown = ModelBrand.symbol("cube")

    /// The brand table. One checked-in file (`Design/model-brands.json`) that `scripts/logo-coverage.py` reads too.
    static let table = BrandTable.bundled

    /// Asset names are `Logo-<slug>`. These are the slugs that ship in the bundle.
    static let bundledSlugs = Set(table.brands.keys)

    static func resolve(_ model: ModelDescriptor) -> ModelBrand {
        if let url = model.cloud?.logoURL { return .remote(url) }
        return resolve(id: model.id, source: model.source)
    }

    /// From a saved model id, for messages whose model is no longer in the list.
    static func resolve(id: String) -> ModelBrand {
        let source: ModelSource
        if id.hasPrefix("apple/") { source = .apple }
        else if id.hasPrefix("gguf/") { source = .gguf }
        else if id.hasPrefix("mlx/") { source = .mlx }
        else { source = .anyrouter }
        return resolve(id: id, source: source)
    }

    private static func resolve(id: String, source: ModelSource) -> ModelBrand {
        switch source {
        case .apple:
            return .symbol("apple.logo")
        case .anyrouter:
            let wire = id.hasPrefix("anyrouter/") ? String(id.dropFirst("anyrouter/".count)) : id
            let owner = wire.split(separator: "/").first.map(String.init) ?? ""
            if owner == "anyrouter" { return .asset(anyRouterMark) }
            return logo(slug(owner: owner, bareName: bare(wire))) ?? tile(bare(wire)) ?? monogram(owner)
        case .gguf, .mlx:
            // "gguf/org/repo/file.gguf" and "mlx/org/repo": the repo name carries the family.
            let parts = id.split(separator: "/").map(String.init)
            let repo = parts.count > 2 ? parts[2] : (parts.last ?? "")
            let owner = parts.count > 1 ? parts[1] : ""
            let byFamily = logo(slug(owner: "", bareName: repo.lowercased()))
            let byOwner = logo(slug(owner: owner, bareName: ""))
            return byFamily ?? byOwner ?? tile(repo) ?? monogram(repo)
        }
    }

    /// Provider slug from the owner prefix, else from the model family.
    static func slug(owner: String, bareName: String) -> String? {
        let key = owner.lowercased()
        if !key.isEmpty {
            let mapped = table.aliases[key] ?? key
            if bundledSlugs.contains(mapped) { return mapped }
        }
        let name = bareName.lowercased()
        return table.families.first { name.hasPrefix($0.prefix) }?.slug
    }

    /// The first letter as an SF Symbol ("t.circle.fill"). Anything but a letter keeps the generic cube.
    static func monogram(_ name: String) -> ModelBrand {
        guard let first = name.lowercased().first, first.isASCII, first.isLetter else { return unknown }
        return .symbol("\(first).circle.fill")
    }

    /// The symbol tile of a family listed under `symbols` in the table, by the bare model or repo name.
    static func tile(_ name: String) -> ModelBrand? {
        let name = name.lowercased()
        return table.symbols.first { name.hasPrefix($0.prefix) }.map { .tile($0.symbol) }
    }

    private static func logo(_ slug: String?) -> ModelBrand? {
        guard let slug else { return nil }
        return ModelBrand.asset("Logo-\(slug)")
    }

    private static func bare(_ wire: String) -> String {
        wire.split(separator: "/").last.map(String.init) ?? wire
    }
}

/// What ModelBrand needs to know about providers, decoded from `Design/model-brands.json`.
struct BrandTable: Decodable, Equatable, Sendable {
    struct Family: Decodable, Equatable, Sendable {
        let prefix: String
        let slug: String
    }

    /// Bundled logo slug to display name.
    let brands: [String: String]
    /// Owner prefixes and display names that map to another logo, as on the web app.
    let aliases: [String: String]
    /// Model family by the bare model name, in the web app's order.
    let families: [Family]
    /// Owners reviewed as having no public mark. They show a monogram. Read by the coverage test and script.
    let noMark: [String]
    /// Model families with no lobe-icons mark, shown as an SF Symbol tile. The coverage script accepts them.
    let symbols: [SymbolFamily]

    struct SymbolFamily: Decodable, Equatable, Sendable {
        let prefix: String
        let symbol: String
    }

    /// A missing or malformed file is a build defect, so it stops loudly; every test run loads it.
    static let bundled: BrandTable = {
        let url = Bundle.main.url(forResource: "model-brands", withExtension: "json")!
        return try! JSONDecoder().decode(BrandTable.self, from: Data(contentsOf: url))
    }()
}
