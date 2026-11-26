import Foundation

enum VoiceModelKind: String, Codable, Sendable, CaseIterable {
    case stt
    case tts
}

/// The runtime that plays a model. `system` is Apple's own and has no files.
enum VoiceEngineKind: String, Codable, Sendable {
    case system
    case whisperKit
    case moonshine
}

struct VoiceModelFile: Codable, Hashable, Sendable {
    /// Where the file goes inside the model's folder.
    var path: String
    var url: URL
    var sizeBytes: Int64
    var sha256: String?
}

enum VoiceCatalogError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidID(String)
    case invalidFile(String)
    case missingBundle

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "The voice catalog version \(version) is not supported."
        case .invalidID(let id): "Voice model id \"\(id)\" is not valid."
        case .invalidFile(let path): "Voice model file \"\(path)\" is not valid."
        case .missingBundle: "voice-models.json is missing from the app bundle."
        }
    }
}

/// One voice model the user can download, or the System engine. Catalog JSON is `catalog/voice-models.json`,
/// written by `scripts/voice-catalog-add.py` from pinned Hugging Face revisions.
struct VoiceModel: Identifiable, Codable, Hashable, Sendable {
    /// Id of the System engine in a selection. It is never in the catalog file.
    static let systemID = "system"

    var id: String
    var kind: VoiceModelKind
    var engine: VoiceEngineKind
    var title: String
    var summary: String?
    /// Language codes the model covers, or `["*"]` for every language it knows.
    var languages: [String]
    /// For display when `languages` is `["*"]`.
    var languageCount: Int?
    /// The model works out the language from the audio itself.
    var detectsLanguage: Bool
    /// Languages the model covers on paper but handles poorly. The app uses the System engine for these.
    var weakLanguages: [String]
    var license: String
    var sourceURL: URL
    /// Smaller sorts first. The recommendation is the largest that runs well.
    var order: Int?
    var sizeBytes: Int64
    /// Memory while running, when it is known. Else a multiple of the download.
    var residentBytes: Int64?
    var files: [VoiceModelFile]

    init(id: String, kind: VoiceModelKind, engine: VoiceEngineKind, title: String, summary: String? = nil,
         languages: [String], languageCount: Int? = nil, detectsLanguage: Bool = false, weakLanguages: [String] = [],
         license: String, sourceURL: URL, order: Int? = nil, sizeBytes: Int64, residentBytes: Int64? = nil,
         files: [VoiceModelFile] = []) {
        self.id = id
        self.kind = kind
        self.engine = engine
        self.title = title
        self.summary = summary
        self.languages = languages
        self.languageCount = languageCount
        self.detectsLanguage = detectsLanguage
        self.weakLanguages = weakLanguages
        self.license = license
        self.sourceURL = sourceURL
        self.order = order
        self.sizeBytes = sizeBytes
        self.residentBytes = residentBytes
        self.files = files
    }

    /// The always-present row of a kind: Apple's own engine, nothing to download.
    static func system(_ kind: VoiceModelKind) -> VoiceModel {
        VoiceModel(
            id: systemID, kind: kind, engine: .system, title: "System",
            summary: kind == .stt ? "Apple's on-device dictation. No download." : "Apple's built-in voices. No download.",
            languages: ["*"], license: "Apple", sourceURL: URL(string: "https://developer.apple.com/documentation/speech")!,
            sizeBytes: 0)
    }

    var isSystem: Bool { engine == .system }

    func supports(_ language: VoiceLanguage) -> Bool {
        languages.contains("*") || languages.contains(language.code)
    }

    func isWeak(for language: VoiceLanguage) -> Bool { weakLanguages.contains(language.code) }

    /// "99 languages", or the names for a short list.
    var languageSummary: String {
        if languages.contains("*") {
            guard let languageCount else { return "Many languages" }
            return "\(languageCount) languages"
        }
        return languages.map { VoiceLanguage($0).name }.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, engine, title, summary, languages, languageCount, detectsLanguage, weakLanguages
        case license, sourceURL, order, sizeBytes, residentBytes, files
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard id.range(of: "^[a-z0-9][a-z0-9._-]{0,63}$", options: .regularExpression) != nil, id != Self.systemID else {
            throw VoiceCatalogError.invalidID(id)
        }
        let files = try c.decodeIfPresent([VoiceModelFile].self, forKey: .files) ?? []
        for file in files {
            guard HuggingFaceAPI.isSafeFilePath(file.path), file.url.scheme == "https", file.sizeBytes > 0 else {
                throw VoiceCatalogError.invalidFile(file.path)
            }
        }
        self.init(
            id: id, kind: try c.decode(VoiceModelKind.self, forKey: .kind),
            engine: try c.decode(VoiceEngineKind.self, forKey: .engine), title: try c.decode(String.self, forKey: .title),
            summary: try c.decodeIfPresent(String.self, forKey: .summary),
            languages: try c.decode([String].self, forKey: .languages),
            languageCount: try c.decodeIfPresent(Int.self, forKey: .languageCount),
            detectsLanguage: try c.decodeIfPresent(Bool.self, forKey: .detectsLanguage) ?? false,
            weakLanguages: try c.decodeIfPresent([String].self, forKey: .weakLanguages) ?? [],
            license: try c.decode(String.self, forKey: .license), sourceURL: try c.decode(URL.self, forKey: .sourceURL),
            order: try c.decodeIfPresent(Int.self, forKey: .order), sizeBytes: try c.decode(Int64.self, forKey: .sizeBytes),
            residentBytes: try c.decodeIfPresent(Int64.self, forKey: .residentBytes), files: files)
    }
}

struct VoiceCatalogDocument: Decodable, Sendable {
    static let supportedVersion = 1
    var version: Int
    var models: [VoiceModel]

    static func decode(_ data: Data) throws -> VoiceCatalogDocument {
        let document = try JSONDecoder().decode(VoiceCatalogDocument.self, from: data)
        guard document.version == supportedVersion else { throw VoiceCatalogError.unsupportedVersion(document.version) }
        return document
    }
}

enum BundledVoiceCatalog {
    private final class Anchor {}

    /// Reads `catalog/voice-models.json` (bundled as `voice-models.json`). A missing or broken file is a build error, so this throws.
    static func load(bundle: Bundle? = nil) throws -> [VoiceModel] {
        let bundle = bundle ?? Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: "voice-models", withExtension: "json") else {
            throw VoiceCatalogError.missingBundle
        }
        return try VoiceCatalogDocument.decode(Data(contentsOf: url)).models
    }
}
