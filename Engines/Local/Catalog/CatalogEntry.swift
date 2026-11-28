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

    /// The catalog badge `experimental`: a size that runs, but slowly or with less accuracy than its full model.
    static let experimental = CatalogBadge(label: "Experimental · slow", tone: "warning")
}

/// Sampling the publisher recommends for a size, and a cap on reply length. Applied over the app's defaults for that
/// model only: a quantized model can loop or ramble with other settings.
struct CatalogSampling: Codable, Hashable, Sendable {
    var temperature: Double?
    var topP: Double?
    /// 0 turns top-k off.
    var topK: Int?
    /// 0 turns min-p off.
    var minP: Double?
    /// The most tokens one reply may take, thinking included.
    var maxOutputTokens: Int?

    func applied(to params: GenerationParams) -> GenerationParams {
        var params = params
        if let temperature { params.temperature = temperature }
        if let topP { params.topP = topP }
        if let maxOutputTokens { params.maxTokens = min(params.maxTokens ?? maxOutputTokens, maxOutputTokens) }
        return params
    }
}

/// The vision companion of a model: the projector file in the same repo.
struct CatalogVision: Codable, Hashable, Sendable {
    var mmprojFile: String
    var mmprojSize: Int64?
    /// Longest side, in pixels, of the photo handed to the projector. Larger photos are shrunk first.
    var imageSide: Int?
    /// True when the projector is an add-on the person downloads later, in the model's page. The model's own download
    /// leaves it out, and the size lists the "vision" capability only while the projector is on disk. Nil means the
    /// projector is part of the model's download.
    var isOptional: Bool?

    private enum CodingKeys: String, CodingKey {
        case mmprojFile, mmprojSize, imageSide
        case isOptional = "optional"
    }
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
    /// Bytes of embedding tables mmap keeps out of RAM, from the GGUF tensor list. Gemma 4's per-layer embeddings are
    /// more than half of its file.
    var lazyWeightBytes: Int64?
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
    /// GGUF only: recommended sampling and reply cap. Nil uses the app's settings.
    var sampling: CatalogSampling?
    /// The family this size belongs to. Nil for a repo the user added.
    var familyID: String?
    var familyName: String?
    var publisher: String?
    var website: String?
    /// A deprecated entry is hidden from browsing and recommendations. It stays here so an installed copy keeps working.
    var status: CatalogStatus
    /// The family that replaces this one, when it is deprecated.
    var replacedBy: String?

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
        memory: CatalogMemory? = nil, sampling: CatalogSampling? = nil, familyID: String? = nil, familyName: String? = nil, publisher: String? = nil,
        website: String? = nil, status: CatalogStatus = .current, replacedBy: String? = nil
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
        self.sampling = sampling
        self.familyID = familyID
        self.familyName = familyName
        self.publisher = publisher
        self.website = website
        self.status = status
        self.replacedBy = replacedBy
    }

    private enum CodingKeys: String, CodingKey {
        case repo, format, file, title, summary, parameters, quantization, sizeBytes
        case contextLength, license, revision, capabilities, order
        case sha256, iconKey, badges, supportsThinking, vision, isOnboarding, platforms, recommended
        case minRAMBytes, createdAt, updatedAt, memory, sampling
        case familyID, familyName, publisher, website, status, replacedBy
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
            memory: try c.decodeIfPresent(CatalogMemory.self, forKey: .memory),
            sampling: try c.decodeIfPresent(CatalogSampling.self, forKey: .sampling),
            familyID: try c.decodeIfPresent(String.self, forKey: .familyID),
            familyName: try c.decodeIfPresent(String.self, forKey: .familyName),
            publisher: try c.decodeIfPresent(String.self, forKey: .publisher),
            website: try c.decodeIfPresent(String.self, forKey: .website),
            status: try c.decodeIfPresent(CatalogStatus.self, forKey: .status) ?? .current,
            replacedBy: try c.decodeIfPresent(String.self, forKey: .replacedBy)
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
        try c.encodeIfPresent(sampling, forKey: .sampling)
        try c.encodeIfPresent(familyID, forKey: .familyID)
        try c.encodeIfPresent(familyName, forKey: .familyName)
        try c.encodeIfPresent(publisher, forKey: .publisher)
        try c.encodeIfPresent(website, forKey: .website)
        if status != .current { try c.encode(status, forKey: .status) }
        try c.encodeIfPresent(replacedBy, forKey: .replacedBy)
    }

    /// What the fit check needs. Uses the catalog's memory facts when present, else a guess from the file size.
    /// Nil when the size is unknown.
    var memoryProfile: ModelMemoryProfile? {
        guard let sizeBytes = sizeBytes.map({ min(max($0, 0), 1 << 50) }) else { return nil }
        let trained = contextLength ?? 0
        let projector = vision?.mmprojSize ?? 0
        guard let memory else {
            var guess = ModelMemoryProfile.estimated(fileBytes: sizeBytes, trainedContext: trained)
            guess.projectorBytes = projector
            return guess
        }
        return ModelMemoryProfile(
            fileBytes: sizeBytes, fullKVBytesPerToken: memory.fullKVBytesPerToken,
            windowKVBytesPerToken: memory.windowKVBytesPerToken ?? 0, windowTokens: memory.windowTokens ?? 0,
            trainedContext: trained, activeFraction: memory.activeFraction, lazyBytes: memory.lazyWeightBytes ?? 0,
            projectorBytes: projector)
    }

    /// Photo support as a download of its own, for a size whose projector is optional. It installs like any GGUF file,
    /// in its own folder with its own manifest and through the same download manager, so the model's files stay as they
    /// were. Its id is the projector file's id.
    var photoAddOn: CatalogEntry? {
        guard format == .gguf, let vision, vision.isOptional == true else { return nil }
        return CatalogEntry(
            repo: repo, format: .gguf, file: vision.mmprojFile, title: "\(title) photo support",
            sizeBytes: vision.mmprojSize, revision: revision, origin: origin)
    }

    /// False when the entry lists platforms and iOS is not one of them (iPad counts as iOS).
    var isAvailableOnThisPlatform: Bool {
        guard let platforms else { return true }
        return platforms.contains { ["ios", "ipados"].contains($0.lowercased()) }
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
