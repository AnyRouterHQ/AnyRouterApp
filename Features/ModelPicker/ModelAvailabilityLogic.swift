import Foundation

/// Why a model cannot be picked right now. One value per reason the app has data for today.
/// Not covered, because nothing in the app tells it yet: a paid-plan requirement, a region limit, and a mini app that
/// does not support a model (a mini app hides those instead of listing them).
enum ModelUnavailableReason: Equatable, Sendable {
    case signIn
    case outOfCredits
    case needsKey(provider: String)
    /// No upstream provider serves the model at the moment.
    case noRoute
    case disabled
    case doesNotFit(neededBytes: Int64)
    case downloadFirst
    /// The engine cannot run it here (Apple Intelligence off, MLX in the Simulator). The note is the engine's own words.
    case unsupportedHere(String?)

    /// What a tap on the row can do about it.
    enum Fix: Equatable, Sendable {
        case signIn, getCredits, addKey, browse

        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .getCredits: "Get credits"
            case .addKey: "Add key"
            case .browse: "Browse models"
            }
        }
    }

    var fix: Fix? {
        switch self {
        case .signIn: .signIn
        case .outOfCredits: .getCredits
        case .needsKey: .addKey
        case .doesNotFit, .downloadFirst: .browse
        case .noRoute, .disabled, .unsupportedHere: nil
        }
    }

    /// One line. `device` is "iPhone" or "iPad".
    func text(device: String) -> String {
        switch self {
        case .signIn: return "Sign in to use"
        case .outOfCredits: return "Out of credits"
        case .needsKey(let provider): return "Add your own key (BYOK) for \(provider)"
        case .noRoute: return "No provider is serving it right now"
        case .disabled: return "Turned off"
        case .doesNotFit(let bytes): return "Doesn't fit this \(device) (needs \(FitFormat.gigabytes(bytes)))"
        case .downloadFirst: return "Download first"
        case .unsupportedHere(let note):
            if let note { return note }
            return "Not available on this device"
        }
    }

    /// Fixable reasons first, in the order a person would act on them.
    fileprivate var rank: Int {
        switch self {
        case .signIn: 0
        case .outOfCredits: 1
        case .needsKey: 2
        case .downloadFirst: 3
        case .doesNotFit: 4
        case .noRoute: 5
        case .disabled: 6
        case .unsupportedHere: 7
        }
    }
}

struct PickerUnavailableModel: Identifiable, Equatable, Sendable {
    var model: ModelDescriptor
    var reason: ModelUnavailableReason

    var id: String { model.id }
}

/// A list of models split into the ones that can be picked now and the ones that cannot, each with its reason.
struct ModelAvailability: Equatable, Sendable {
    var available: [ModelDescriptor] = []
    var unavailable: [PickerUnavailableModel] = []
}

/// The one place that decides whether a model can be picked and, if not, why.
enum ModelAvailabilityLogic {
    /// `fit` is the device-fit numbers of a local model, `engineNote` the engine's reason it cannot run here.
    static func reason(
        for model: ModelDescriptor, signedIn: Bool, summary: AccountSummary? = nil,
        fit: FitDetail? = nil, engineNote: String? = nil
    ) -> ModelUnavailableReason? {
        switch model.source {
        case .anyrouter:
            return cloudReason(model, signedIn: signedIn, summary: summary)
        case .apple:
            return model.isInstalled ? nil : .unsupportedHere(model.summary)
        case .gguf, .mlx:
            if let engineNote { return .unsupportedHere(engineNote) }
            if let fit, fit.verdict == .wontFit { return .doesNotFit(neededBytes: fit.neededBytes) }
            return model.isInstalled ? nil : .downloadFirst
        }
    }

    static func partition(
        _ models: [ModelDescriptor], signedIn: Bool, summary: AccountSummary? = nil,
        fit: (ModelDescriptor) -> FitDetail? = { _ in nil }, engineNote: (ModelDescriptor) -> String? = { _ in nil }
    ) -> ModelAvailability {
        var result = ModelAvailability()
        for model in models {
            let why = reason(for: model, signedIn: signedIn, summary: summary, fit: fit(model), engineNote: engineNote(model))
            if let why { result.unavailable.append(PickerUnavailableModel(model: model, reason: why)) } else { result.available.append(model) }
        }
        result.unavailable.sort { lhs, rhs in
            if lhs.reason.rank != rhs.reason.rank { return lhs.reason.rank < rhs.reason.rank }
            return lhs.model.displayName.localizedCaseInsensitiveCompare(rhs.model.displayName) == .orderedAscending
        }
        return result
    }

    /// Everything the Local tab considers: Apple and local models the app lists, plus catalog models that are not on
    /// the device yet (shown as "Download first").
    static func localCandidates(listed: [ModelDescriptor], catalog: [LocalModelEntry]) -> [ModelDescriptor] {
        let local = listed.filter { $0.source != .anyrouter }
        let known = Set(local.map(\.id))
        let missing = catalog.map(\.descriptor).filter { !known.contains($0.id) }.map { model -> ModelDescriptor in
            var copy = model
            copy.isInstalled = false
            return copy
        }
        return local + missing
    }

    // MARK: - Cloud

    private static func cloudReason(_ model: ModelDescriptor, signedIn: Bool, summary: AccountSummary?) -> ModelUnavailableReason? {
        switch model.cloud?.availability {
        case .noRoute: return .noRoute
        case .disabled: return .disabled
        case .needsKey: return signedIn ? .needsKey(provider: providerName(model)) : .signIn
        case .usable, nil: break
        }
        if !signedIn { return .signIn }
        // Signed in and routable, yet the list does not call it usable.
        if !model.isInstalled { return .noRoute }
        return isOutOfCredits(model, summary: summary) ? .outOfCredits : nil
    }

    /// Only when the balance is known and empty, the model is billed to credits, and no free requests are left to spend.
    private static func isOutOfCredits(_ model: ModelDescriptor, summary: AccountSummary?) -> Bool {
        guard let credits = summary?.credits, credits.balance <= 0 else { return false }
        if let pricing = model.cloud?.pricing, pricing.isFree || pricing.billing == .byok { return false }
        if let free = summary?.freeRequests, free.remaining > 0 { return false }
        return true
    }

    private static func providerName(_ model: ModelDescriptor) -> String {
        if let name = model.cloud?.providerName { return name }
        if let slug = model.cloudProvider { return ModelPickerLogic.providerTitle(slug) }
        return "this provider"
    }
}
