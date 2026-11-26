import Foundation

enum LocalModelFormat: String, Codable, Sendable, CaseIterable {
    case gguf
    case mlx
}

/// Where a catalog entry came from. Not part of the JSON; set when catalogs are merged.
enum CatalogOrigin: Int, Sendable, Comparable {
    case bundled = 0
    case remote = 1
    case user = 2

    static func < (lhs: CatalogOrigin, rhs: CatalogOrigin) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A short label on a catalog card. `tone` is one of "info", "success", "warning"; anything else renders neutral.
struct CatalogBadge: Codable, Hashable, Sendable {
    var label: String
    var tone: String?
}

/// The vision companion of a model: the projector file in the same repo. Data only until image input ships.
struct CatalogVision: Codable, Hashable, Sendable {
    var mmprojFile: String
    var mmprojSize: Int64?
}

/// Memory facts read from the model's metadata, so the fit check does not guess. Written by `scripts/catalog-add.sh`.
struct CatalogMemory: Codable, Hashable, Sendable {
    /// KV-cache bytes per token over layers that attend to the whole context (f16 cache).
    var fullKVBytesPerToken: Int64
    /// KV-cache bytes per token over sliding-window layers, and their window.
    var windowKVBytesPerToken: Int64?
    var windowTokens: Int?
    /// Mixture of experts: share of the weights one token touches.
    var activeFraction: Double?
}

/// One downloadable local model: a single GGUF file, or a whole MLX repo snapshot.
struct CatalogEntry: Identifiable, Hashable, Codable, Sendable {
    /// Hugging Face repo id, `org/name`.
    var repo: String
    var format: LocalModelFormat
    /// GGUF only: the `.gguf` file inside the repo.
    var file: String?
    var title: String
    var summary: String?
    /// Display only, e.g. "1.7B".
    var parameters: String?
    /// Display only, e.g. "Q4_K_M" or "4-bit".
    var quantization: String?
    /// Download size. The GGUF file, or the sum of the MLX snapshot files.
    var sizeBytes: Int64?
    var contextLength: Int?
    var license: String?
    /// Commit sha or branch to download from. `main` when nil.
    var revision: String?
    var capabilities: Set<String>
    /// Smaller sorts first. Entries without one sort last.
    var order: Int?
    var origin: CatalogOrigin
    /// GGUF only: expected sha256 of the file. A download whose Hugging Face listing says otherwise is refused.
    var sha256: String?
    /// Short key the UI maps to an icon, e.g. "gemma". Unknown keys fall back to a generic icon.
    var iconKey: String?
    var badges: [CatalogBadge]
    var supportsThinking: Bool
    var vision: CatalogVision?
    /// Offered first in onboarding.
    var isOnboarding: Bool
    /// "ios", "ipados", ... Nil means every platform.
    var platforms: [String]?
    /// Shown as a top pick.
    var recommended: Bool
    /// RAM below which the model should not be offered as runnable. Nil means use the size estimate.
    var minRAMBytes: Int64?
    /// ISO dates (`yyyy-MM-dd`).
    var createdAt: String?
    var updatedAt: String?
    var memory: CatalogMemory?

    /// Matches `ModelDescriptor.id`: `gguf/<repo>/<file>` or `mlx/<repo>`.
    var id: String {
        switch format {
        case .gguf: "gguf/\(repo)/\(file ?? "")"
        case .mlx: "mlx/\(repo)"
        }
    }

    init(
        repo: String, format: LocalModelFormat, file: String? = nil, title: String,
        summary: String? = nil, parameters: String? = nil, quantization: String? = nil,
        sizeBytes: Int64? = nil, contextLength: Int? = nil, license: String? = nil,
        revision: String? = nil, capabilities: Set<String> = ["chat"], order: Int? = nil,
        origin: CatalogOrigin = .bundled, sha256: String? = nil, iconKey: String? = nil,
        badges: [CatalogBadge] = [], supportsThinking: Bool = false, vision: CatalogVision? = nil,
        isOnboarding: Bool = false, platforms: [String]? = nil, recommended: Bool = false,
        minRAMBytes: Int64? = nil, createdAt: String? = nil, updatedAt: String? = nil,
        memory: CatalogMemory? = nil
    ) {
        self.repo = repo
        self.format = format
        self.file = file
        self.title = title
        self.summary = summary
        self.parameters = parameters
        self.quantization = quantization
        self.sizeBytes = sizeBytes
        self.contextLength = contextLength
        self.license = license
        self.revision = revision
        self.capabilities = capabilities
        self.order = order
        self.origin = origin
        self.sha256 = sha256
        self.iconKey = iconKey
        self.badges = badges
        self.supportsThinking = supportsThinking
        self.vision = vision
        self.isOnboarding = isOnboarding
        self.platforms = platforms
        self.recommended = recommended
        self.minRAMBytes = minRAMBytes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.memory = memory
    }

    private enum CodingKeys: String, CodingKey {
        case repo, format, file, title, summary, parameters, quantization, sizeBytes
        case contextLength, license, revision, capabilities, order
        case sha256, iconKey, badges, supportsThinking, vision, isOnboarding, platforms, recommended
        case minRAMBytes, createdAt, updatedAt, memory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let repo = try c.decode(String.self, forKey: .repo)
        let format = try c.decode(LocalModelFormat.self, forKey: .format)
        let file = try c.decodeIfPresent(String.self, forKey: .file)
        guard HuggingFaceAPI.isValidRepo(repo) else { throw LocalModelError.invalidRepo(repo) }
        if format == .gguf {
            guard let file, HuggingFaceAPI.isSafeFilePath(file) else {
                throw LocalModelError.invalidFilePath(file ?? "(missing)")
            }
        }
        self.init(
            repo: repo, format: format, file: file,
            title: try c.decode(String.self, forKey: .title),
            summary: try c.decodeIfPresent(String.self, forKey: .summary),
            parameters: try c.decodeIfPresent(String.self, forKey: .parameters),
            quantization: try c.decodeIfPresent(String.self, forKey: .quantization),
            sizeBytes: try c.decodeIfPresent(Int64.self, forKey: .sizeBytes),
            contextLength: try c.decodeIfPresent(Int.self, forKey: .contextLength),
            license: try c.decodeIfPresent(String.self, forKey: .license),
            revision: try c.decodeIfPresent(String.self, forKey: .revision),
            capabilities: try c.decodeIfPresent(Set<String>.self, forKey: .capabilities) ?? ["chat"],
            order: try c.decodeIfPresent(Int.self, forKey: .order),
            sha256: try c.decodeIfPresent(String.self, forKey: .sha256)?.lowercased(),
            iconKey: try c.decodeIfPresent(String.self, forKey: .iconKey),
            badges: try c.decodeIfPresent([CatalogBadge].self, forKey: .badges) ?? [],
            supportsThinking: try c.decodeIfPresent(Bool.self, forKey: .supportsThinking) ?? false,
            vision: try c.decodeIfPresent(CatalogVision.self, forKey: .vision),
            isOnboarding: try c.decodeIfPresent(Bool.self, forKey: .isOnboarding) ?? false,
            platforms: try c.decodeIfPresent([String].self, forKey: .platforms),
            recommended: try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false,
            minRAMBytes: try c.decodeIfPresent(Int64.self, forKey: .minRAMBytes),
            createdAt: try c.decodeIfPresent(String.self, forKey: .createdAt),
            updatedAt: try c.decodeIfPresent(String.self, forKey: .updatedAt),
            memory: try c.decodeIfPresent(CatalogMemory.self, forKey: .memory)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repo, forKey: .repo)
        try c.encode(format, forKey: .format)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(parameters, forKey: .parameters)
        try c.encodeIfPresent(quantization, forKey: .quantization)
        try c.encodeIfPresent(sizeBytes, forKey: .sizeBytes)
        try c.encodeIfPresent(contextLength, forKey: .contextLength)
        try c.encodeIfPresent(license, forKey: .license)
        try c.encodeIfPresent(revision, forKey: .revision)
        try c.encode(capabilities.sorted(), forKey: .capabilities)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(sha256, forKey: .sha256)
        try c.encodeIfPresent(iconKey, forKey: .iconKey)
        if !badges.isEmpty { try c.encode(badges, forKey: .badges) }
        if supportsThinking { try c.encode(true, forKey: .supportsThinking) }
        try c.encodeIfPresent(vision, forKey: .vision)
        if isOnboarding { try c.encode(true, forKey: .isOnboarding) }
        try c.encodeIfPresent(platforms, forKey: .platforms)
        if recommended { try c.encode(true, forKey: .recommended) }
        try c.encodeIfPresent(minRAMBytes, forKey: .minRAMBytes)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(memory, forKey: .memory)
    }

    /// What the fit check needs. Uses the catalog's memory facts when present, else a guess from the file size.
    /// Nil when the size is unknown.
    var memoryProfile: ModelMemoryProfile? {
        guard let sizeBytes else { return nil }
        let trained = contextLength ?? 0
        guard let memory else { return .estimated(fileBytes: sizeBytes, trainedContext: trained) }
        return ModelMemoryProfile(
            fileBytes: sizeBytes, fullKVBytesPerToken: memory.fullKVBytesPerToken,
            windowKVBytesPerToken: memory.windowKVBytesPerToken ?? 0, windowTokens: memory.windowTokens ?? 0,
            trainedContext: trained, activeFraction: memory.activeFraction)
    }

    /// False when the entry lists platforms and iOS is not one of them (iPad counts as iOS).
    var isAvailableOnThisPlatform: Bool {
        guard let platforms else { return true }
        return platforms.contains { ["ios", "ipados"].contains($0.lowercased()) }
    }
}

/// The JSON shape of `catalog.json` and of a remote catalog.
struct CatalogDocument: Codable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var updatedAt: String?
    var models: [CatalogEntry]

    static func decode(_ data: Data) throws -> CatalogDocument {
        // Read the version first so a newer schema reports its version, not a decoding error.
        struct Header: Decodable { var schemaVersion: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion <= supportedSchemaVersion else {
            throw LocalModelError.unsupportedCatalogVersion(header.schemaVersion)
        }
        return try JSONDecoder().decode(CatalogDocument.self, from: data)
    }
}

enum CatalogMerger {
    /// Same id: the higher origin wins (user over remote over bundled).
    /// Result order is fixed: `order`, then title, then id. The input order never matters.
    static func merge(
        bundled: [CatalogEntry] = [], remote: [CatalogEntry] = [], user: [CatalogEntry] = []
    ) -> [CatalogEntry] {
        var byID: [String: CatalogEntry] = [:]
        let sources: [(CatalogOrigin, [CatalogEntry])] = [(.bundled, bundled), (.remote, remote), (.user, user)]
        for (origin, entries) in sources {
            for var entry in entries {
                entry.origin = origin
                byID[entry.id] = entry
            }
        }
        return byID.values.sorted { lhs, rhs in
            let l = lhs.order ?? Int.max
            let r = rhs.order ?? Int.max
            if l != r { return l < r }
            // Plain lowercase compare: locale-aware compare would reorder per device language.
            let lt = lhs.title.lowercased()
            let rt = rhs.title.lowercased()
            if lt != rt { return lt < rt }
            return lhs.id < rhs.id
        }
    }
}
