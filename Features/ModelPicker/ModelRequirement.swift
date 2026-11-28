import Foundation

/// What a model must do to be listed in the picker. The chat takes every chat model; a mini app narrows the list, and
/// a model that does not meet it is hidden, not dimmed.
struct ModelRequirement: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case chat, decision }

    var kind: Kind
    /// A photo is attached, so only models that read images fit.
    var needsVision = false

    static let chat = ModelRequirement(kind: .chat)

    static func decision(needsVision: Bool) -> ModelRequirement { ModelRequirement(kind: .decision, needsVision: needsVision) }

    /// Decision models run on AnyRouter only, so no local model meets a decision requirement.
    var allowsLocal: Bool { kind == .chat }

    /// The models that meet the requirement, usable or not, in list order. `.chat` is every chat model as listed.
    func models(chat: [ModelDescriptor], decision: [ModelDescriptor]) -> [ModelDescriptor] {
        let listed = kind == .chat ? chat : decision
        guard needsVision else { return listed }
        return listed.filter { $0.capabilities.contains("vision") }
    }
}

extension ModelStore {
    /// The models the picker and a mini app consider for `requirement`.
    func listed(for requirement: ModelRequirement) -> [ModelDescriptor] {
        requirement.models(chat: models, decision: decisionModels)
    }
}

/// Which model a mini app runs.
enum MiniAppModelChoice {
    /// The first of `ids` (wire ids: the person's pick, then the app's preferred and fallback models) that is in
    /// `candidates` and usable now, else the first usable candidate. Usable means signed in for a cloud model and
    /// downloaded for a local one (`isInstalled`). `candidates` already meet the app's requirement, so a photo leaves
    /// out every model that cannot read it. Nil when nothing can run the app.
    static func choose(_ ids: [String?], from candidates: [ModelDescriptor]) -> ModelDescriptor? {
        let usable = candidates.filter(\.isInstalled)
        for id in ids.compactMap({ $0 }) {
            if let match = usable.first(where: { $0.wireID == id }) { return match }
        }
        return usable.first
    }
}

/// The model the person picked in each mini app, by app key, as a wire id. Kept apart from the chat's default model.
struct MiniAppModelPicks {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pick(for app: String) -> String? { defaults.string(forKey: key(app)) }

    func remember(_ model: ModelDescriptor, for app: String) { defaults.set(model.wireID, forKey: key(app)) }

    private func key(_ app: String) -> String { "miniApps.model.\(app)" }
}
