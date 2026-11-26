import Foundation

/// Which logo a model shows. Pure, so the mapping is tested without a view.
///
/// Slugs follow the AnyRouter web app (provider aliases and model families), so both apps agree.
/// A logo URL from the API wins. The bundled monochrome set is the fallback, then an SF Symbol.
enum ModelBrand: Equatable {
    /// A bundled template image in the asset catalog.
    case asset(String)
    /// A logo served by the API.
    case remote(URL)
    case symbol(String)

    static let anyRouterMark = "BrandMark"
    static let unknown = ModelBrand.symbol("cube")

    /// Asset names are `Logo-<slug>`. These are the slugs that ship in the bundle.
    static let bundledSlugs: Set<String> = [
        "openai", "anthropic", "google", "meta", "mistral", "qwen", "deepseek", "xai", "cohere",
        "nvidia", "z-ai", "moonshotai", "perplexity", "microsoft", "aws", "huggingface", "liquid",
        "minimax", "stepfun", "ai21", "groq", "openrouter", "fireworks", "together", "baidu",
        "bytedance", "ollama",
    ]

    /// Owner prefixes and display names that map to another logo, as on the web app.
    private static let providerAliases: [String: String] = [
        "meta-llama": "meta", "metallama": "meta", "mistralai": "mistral", "mistral-ai": "mistral",
        "x-ai": "xai", "deepseek-ai": "deepseek", "zhipu": "z-ai", "zhipuai": "z-ai", "zhipu-ai": "z-ai",
        "zai": "z-ai", "zai-org": "z-ai", "chatglm": "z-ai", "moonshot": "moonshotai", "moonshot-ai": "moonshotai",
        "kimi": "moonshotai", "amazon": "aws", "amazon-bedrock": "aws", "msft": "microsoft", "alibaba": "qwen",
        "google-deepmind": "google", "google-vertex": "google", "vertex": "google", "stepfun-ai": "stepfun",
        "hf": "huggingface", "ollama-cloud": "ollama",
    ]

    /// Model family by the bare model name, in the web app's order.
    private static let familyPatterns: [(prefix: String, slug: String)] = [
        ("claude", "anthropic"), ("gpt", "openai"), ("gemini", "google"), ("gemma", "google"),
        ("llama", "meta"), ("mistral", "mistral"), ("mixtral", "mistral"), ("codestral", "mistral"),
        ("ministral", "mistral"), ("deepseek", "deepseek"), ("glm", "z-ai"), ("qwen", "qwen"),
        ("grok", "xai"), ("command", "cohere"), ("step", "stepfun"), ("nemotron", "nvidia"),
        ("phi", "microsoft"), ("lfm", "liquid"), ("smollm", "huggingface"),
    ]

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
            return logo(slug(owner: owner, bareName: bare(wire))) ?? unknown
        case .gguf, .mlx:
            // "gguf/org/repo/file.gguf" and "mlx/org/repo": the repo name carries the family.
            let parts = id.split(separator: "/").map(String.init)
            let repo = parts.count > 2 ? parts[2] : (parts.last ?? "")
            let owner = parts.count > 1 ? parts[1] : ""
            let byFamily = logo(slug(owner: "", bareName: repo.lowercased()))
            let byOwner = logo(slug(owner: owner, bareName: ""))
            return byFamily ?? byOwner ?? ModelBrand.symbol("cpu")
        }
    }

    /// Provider slug from the owner prefix, else from the model family.
    static func slug(owner: String, bareName: String) -> String? {
        let key = owner.lowercased()
        if !key.isEmpty {
            let mapped = providerAliases[key] ?? key
            if bundledSlugs.contains(mapped) { return mapped }
        }
        let name = bareName.lowercased()
        return familyPatterns.first { name.hasPrefix($0.prefix) }?.slug
    }

    private static func logo(_ slug: String?) -> ModelBrand? {
        guard let slug else { return nil }
        return ModelBrand.asset("Logo-\(slug)")
    }

    private static func bare(_ wire: String) -> String {
        wire.split(separator: "/").last.map(String.init) ?? wire
    }
}
