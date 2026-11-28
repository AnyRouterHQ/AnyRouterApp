import Foundation

/// What a tap on a cloud model does. Signed out, a cloud model asks the person to sign in first.
enum CloudTapAction: Equatable {
    case select, signIn, explainKey, ignore
}

enum CloudSignInOutcome: Equatable {
    /// Signed in and the model can be used: it is the pick.
    case selected(ModelDescriptor)
    /// Signed in, but the model cannot be used with this account (it needs a provider key).
    case signedInOnly
    /// The sign-in window was closed, or it failed without an error.
    case stillSignedOut
}

enum CloudSignInLogic {
    static func tap(_ model: ModelDescriptor, signedIn: Bool) -> CloudTapAction {
        if model.source == .anyrouter && !signedIn { return .signIn }
        if model.isInstalled { return .select }
        return model.cloud?.availability == .needsKey ? .explainKey : .ignore
    }

    /// Signs in (or up), reloads the list with the new key, and finds the tapped model in it so it can be picked.
    /// `requirement` is the picker's, so a decision model is found among the decision models.
    @MainActor
    static func signIn(
        mode: AuthMode, then model: ModelDescriptor, account: any AccountService, models: ModelStore,
        requirement: ModelRequirement = .chat
    ) async throws -> CloudSignInOutcome {
        try await account.signIn(mode: mode)
        guard account.state.isSignedIn else { return .stillSignedOut }
        await models.refresh()
        if let fresh = models.listed(for: requirement).first(where: { $0.id == model.id && $0.isInstalled }) { return .selected(fresh) }
        return .signedInOnly
    }
}
