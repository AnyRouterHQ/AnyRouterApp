import Foundation

enum CatalogStatus: String, Codable, Sendable {
    case current
    case deprecated
}

/// One downloadable size of a family: a GGUF file or an MLX snapshot.
struct CatalogVariant: Decodable, Hashable, Sendable {
    var repo: String
    var engine: LocalModelFormat
    /// GGUF only.
    var file: String?
    /// "4B", "E2B": what the size is called.
    var params: String
    var quant: String?
    var sizeBytes: Int64
    var contextLength: Int?
    var license: String?
    var revision: String?
    var sha256: String?
    var vision: CatalogVision?
    var isOnboarding = false
    var platforms: [String]?
    var minRAMBytes: Int64?
    var memory: CatalogMemory?
    var createdAt: String?
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case repo, engine, file, params, quant, sizeBytes, contextLength, license, revision, sha256, vision
        case isOnboarding, platforms, minRAMBytes, memory, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repo = try c.decode(String.self, forKey: .repo)
        engine = try c.decode(LocalModelFormat.self, forKey: .engine)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        guard HuggingFaceAPI.isValidRepo(repo) else { throw LocalModelError.invalidRepo(repo) }
        if engine == .gguf {
            guard let file, HuggingFaceAPI.isSafeFilePath(file) else {
                throw LocalModelError.invalidFilePath(file ?? "(missing)")
            }
        }
        params = try c.decode(String.self, forKey: .params)
        quant = try c.decodeIfPresent(String.self, forKey: .quant)
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)?.lowercased()
        vision = try c.decodeIfPresent(CatalogVision.self, forKey: .vision)
        isOnboarding = try c.decodeIfPresent(Bool.self, forKey: .isOnboarding) ?? false
        platforms = try c.decodeIfPresent([String].self, forKey: .platforms)
        minRAMBytes = try c.decodeIfPresent(Int64.self, forKey: .minRAMBytes)
        memory = try c.decodeIfPresent(CatalogMemory.self, forKey: .memory)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// A model line at one generation, with its sizes. This is what the model browser lists first.
struct CatalogFamily: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var publisher: String
    /// The model line across generations ("gemma"). At most one current family per line.
    var line: String
    /// A short key the UI maps to a logo ("gemma", "qwen"). Unknown keys fall back to a generic mark.
    var logo: String
    var summary: String
    var website: String
    /// "thinking", "vision", "audio", "tools", "code", "multilingual".
    var tags: [String]
    /// "best", "recommended", "new".
    var badges: [String]
    var status: CatalogStatus
    var replacedBy: String?
    var order: Int?
    var variants: [CatalogVariant]

    private enum CodingKeys: String, CodingKey {
        case id, name, publisher, line, logo, summary, website, tags, badges, status, replacedBy, order, variants
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        publisher = try c.decode(String.self, forKey: .publisher)
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? id
        logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        badges = try c.decodeIfPresent([String].self, forKey: .badges) ?? []
        status = try c.decodeIfPresent(CatalogStatus.self, forKey: .status) ?? .current
        replacedBy = try c.decodeIfPresent(String.self, forKey: .replacedBy)
        order = try c.decodeIfPresent(Int.self, forKey: .order)
        variants = try c.decode([CatalogVariant].self, forKey: .variants)
    }

    /// The family's sizes as the entries the rest of the app works with. Family facts are copied onto each.
    func entries(familyIndex: Int) -> [CatalogEntry] {
        // "vision" is a fact of a size, not of a family: only a GGUF size with a projector takes photos.
        let familyCapabilities = Set(["chat"] + tags.filter { $0 != "vision" }.map { $0 == "thinking" ? "reasoning" : $0 })
        let badgeList = badges.map { CatalogBadge(label: $0.capitalized, tone: $0 == "new" ? "success" : "info") }
        let isRecommended = badges.contains("recommended") || badges.contains("best")
        return variants.enumerated().map { index, variant in
            let capabilities = variant.vision == nil ? familyCapabilities : familyCapabilities.union(["vision"])
            return CatalogEntry(
                repo: variant.repo, format: variant.engine, file: variant.file,
                title: "\(name) \(variant.params)" + (variant.engine == .mlx ? " (MLX)" : ""),
                summary: summary, parameters: variant.params, quantization: variant.quant, sizeBytes: variant.sizeBytes,
                contextLength: variant.contextLength, license: variant.license, revision: variant.revision,
                capabilities: capabilities, order: (order ?? familyIndex) * 100 + index, sha256: variant.sha256, iconKey: logo,
                badges: badgeList, supportsThinking: tags.contains("thinking"), vision: variant.vision,
                isOnboarding: variant.isOnboarding, platforms: variant.platforms, recommended: isRecommended,
                minRAMBytes: variant.minRAMBytes, createdAt: variant.createdAt, updatedAt: variant.updatedAt,
                memory: variant.memory, familyID: id, familyName: name, publisher: publisher, website: website,
                status: status, replacedBy: replacedBy)
        }
    }
}

/// The catalog file, `catalog/models.json`, and a remote copy of it: families with their sizes.
struct CatalogDocument: Sendable {
    static let supportedSchemaVersion = 2

    var schemaVersion: Int
    var updatedAt: String?
    var families: [CatalogFamily]
    /// Every size of every family, as entries, in file order.
    var models: [CatalogEntry]

    init(schemaVersion: Int, updatedAt: String?, families: [CatalogFamily]) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.families = families
        self.models = families.enumerated().flatMap { $0.element.entries(familyIndex: $0.offset) }
    }

    /// A document from loose entries, for sources that have no families (tests, a repo list).
    init(schemaVersion: Int, updatedAt: String?, models: [CatalogEntry]) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.families = []
        self.models = models
    }

    static func decode(_ data: Data) throws -> CatalogDocument {
        // Read the version first so a newer schema reports its version, not a decoding error.
        struct Header: Decodable { var schemaVersion: Int }
        struct Body: Decodable {
            var schemaVersion: Int
            var updatedAt: String?
            var families: [CatalogFamily]
        }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion == supportedSchemaVersion else {
            throw LocalModelError.unsupportedCatalogVersion(header.schemaVersion)
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        return CatalogDocument(schemaVersion: body.schemaVersion, updatedAt: body.updatedAt, families: body.families)
    }
}
