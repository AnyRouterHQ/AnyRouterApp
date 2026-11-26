import Foundation

/// One group of models in the picker.
struct PickerSection: Identifiable, Equatable {
    enum Kind: Hashable {
        case apple
        /// AnyRouter's own routers, "AnyRouter" (auto) first.
        case anyrouter
        case local
        /// Other cloud models, one group per provider.
        case provider(String)
    }

    var kind: Kind
    var models: [ModelDescriptor]

    var id: String {
        switch kind {
        case .apple: "apple"
        case .anyrouter: "anyrouter"
        case .local: "local"
        case .provider(let name): "provider/\(name)"
        }
    }

    var title: String {
        switch kind {
        case .apple: "Apple Intelligence"
        case .anyrouter: "AnyRouter"
        case .local: "On this device"
        case .provider(let name): ModelPickerLogic.providerTitle(name)
        }
    }
}

enum ModelPickerLogic {
    static let autoSubtitle = "Picks the best model for each message"

    /// Routers after "AnyRouter" (auto), in this order. Others follow alphabetically.
    private static let routerOrder = ["coding", "agent", "free", "latest", "decision"]

    private static let providerNames = [
        "openai": "OpenAI", "x-ai": "xAI", "deepseek": "DeepSeek", "meta-llama": "Meta Llama",
        "mistralai": "Mistral AI", "qwen": "Qwen", "google": "Google", "anthropic": "Anthropic",
    ]

    /// Usable models only, in this order: Apple, AnyRouter routers, local (GGUF and MLX), then
    /// one group per cloud provider. The AnyRouter group is always present without a query so
    /// the sign-in prompt has a home. `anyrouter/byok` is left out unless the query finds it.
    static func sections(models: [ModelDescriptor], query: String) -> [PickerSection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !needle.isEmpty
        let candidates = models.filter { model in
            guard model.isInstalled else { return false }
            if searching { return matches(model, needle) }
            return model.id != ModelDescriptor.byokRouterID
        }

        var apple: [ModelDescriptor] = []
        var routers: [ModelDescriptor] = []
        var local: [ModelDescriptor] = []
        var providers: [String: [ModelDescriptor]] = [:]
        for model in candidates {
            switch model.source {
            case .apple: apple.append(model)
            case .gguf, .mlx: local.append(model)
            case .anyrouter:
                if model.isRouter { routers.append(model) } else { providers[model.cloudProvider ?? "other", default: []].append(model) }
            }
        }

        var result: [PickerSection] = [
            PickerSection(kind: .apple, models: byName(apple)),
            PickerSection(kind: .anyrouter, models: orderedRouters(routers)),
            PickerSection(kind: .local, models: byName(local)),
        ]
        result += providers
            .map { PickerSection(kind: .provider($0.key), models: byName($0.value)) }
            .sorted { providerTitle($0.kind.providerName).localizedCaseInsensitiveCompare(providerTitle($1.kind.providerName)) == .orderedAscending }
        return result.filter { !$0.models.isEmpty || (!searching && $0.kind == .anyrouter) }
    }

    /// Short caption under a model name.
    static func subtitle(for model: ModelDescriptor) -> String {
        switch model.source {
        case .apple: return "On device"
        case .anyrouter:
            if model.id == ModelDescriptor.autoRouterID { return autoSubtitle }
            if model.isRouter { return model.summary.map(shortSummary) ?? "AnyRouter" }
            return model.cloudProvider.map(providerTitle) ?? "Cloud"
        case .gguf, .mlx:
            let kind = model.source == .gguf ? "GGUF" : "MLX"
            guard let size = model.sizeBytes else { return kind }
            return "\(kind) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
    }

    /// First sentence of a provider description, capped so it fits one line.
    static func shortSummary(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let sentence = line.range(of: ". ").map { String(line[..<$0.lowerBound]) } ?? line
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.count > 80 ? String(trimmed.prefix(79)) + "…" : trimmed
    }

    static func providerTitle(_ name: String) -> String {
        providerNames[name] ?? name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: - Private

    /// Matches the name, the short name or the provider-qualified id. The `anyrouter/` prefix is
    /// not searched, or every cloud model would match "anyrouter".
    static func matches(_ model: ModelDescriptor, _ needle: String) -> Bool {
        [model.displayName, model.shortName].contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            || model.wireID.range(of: needle, options: .caseInsensitive) != nil
    }

    private static func byName(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func orderedRouters(_ routers: [ModelDescriptor]) -> [ModelDescriptor] {
        func rank(_ model: ModelDescriptor) -> Int {
            if model.id == ModelDescriptor.autoRouterID { return -1 }
            let slug = String(model.wireID.dropFirst("anyrouter/".count))
            return routerOrder.firstIndex(of: slug) ?? routerOrder.count
        }
        return routers.sorted {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

private extension PickerSection.Kind {
    var providerName: String {
        if case .provider(let name) = self { return name }
        return ""
    }
}
