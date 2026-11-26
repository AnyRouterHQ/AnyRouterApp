import Foundation
import Testing

@testable import AnyRouter

/// Account that signs in when told to, and remembers how it was asked.
@MainActor @Observable
final class SignInTestAccount: AccountService {
    private(set) var state: AccountState = .signedOut
    var summary: AccountSummary? { nil }
    private(set) var modes: [AuthMode] = []
    /// What the browser sign-in does: finish signed in, close without a key, or fail.
    enum Behavior { case signsIn, cancels, fails }
    var behavior = Behavior.signsIn
    let signedIn: Flag

    struct Refused: LocalizedError { var errorDescription: String? { "Sign-in is down." } }

    init(signedIn: Flag) { self.signedIn = signedIn }

    func signIn(mode: AuthMode) async throws {
        modes.append(mode)
        switch behavior {
        case .signsIn:
            state = .signedIn(label: nil)
            signedIn.value = true
        case .cancels: break
        case .fails: throw Refused()
        }
    }

    func signOut() async {}
    func refreshSummary() async {}
}

/// An AnyRouter engine whose models can be used only once the person is signed in, like the real one.
struct GatedCloudEngine: ChatEngine {
    let source = ModelSource.anyrouter
    let signedIn: Flag
    /// A model that still needs the person's own provider key after sign-in.
    var needsKeyAfterSignIn = false

    func availableModels() async throws -> [ModelDescriptor] {
        [testModel(id: "anyrouter/openai/gpt", source: .anyrouter, installed: signedIn.value && !needsKeyAfterSignIn)]
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
struct CloudSignInTests {
    private func rig(needsKey: Bool = false) async -> (account: SignInTestAccount, models: ModelStore, tapped: ModelDescriptor) {
        let signedIn = Flag()
        let registry = EngineRegistry()
        registry.register(GatedCloudEngine(signedIn: signedIn, needsKeyAfterSignIn: needsKey))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return (SignInTestAccount(signedIn: signedIn), models, models.models[0])
    }

    // MARK: the signed-out list

    @Test func theSignedOutCatalogReadsEveryRoutableModelAsUsableAndRowsLookNormal() throws {
        let body = """
            {"data":[
              {"id":"openai/mini","category":"text","can_route":false,"can_route_reason":"needs_key",
               "pricing":{"input_per_1m":0.4,"output_per_1m":2,"billing":"credits"}},
              {"id":"vendor/off","category":"text","can_route":false,"can_route_reason":"disabled"}
            ]}
            """
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(body.utf8))
        let signedOut = response.descriptors(usable: false)
        let mini = try #require(signedOut.first { $0.id == "anyrouter/openai/mini" })
        #expect(mini.cloud?.availability == .usable)
        #expect(!mini.isInstalled, "nothing can be used before sign-in")
        let row = PickerRow.make(mini)
        #expect(!row.isDimmed && !row.needsKey)
        #expect(!row.details.contains(PickerRow.needsKeyText))
        // Signed in, the same entry still says it needs the person's own key.
        let signedIn = try #require(response.descriptors(usable: true).first { $0.id == mini.id })
        #expect(signedIn.cloud?.availability == .needsKey)
    }

    @Test func signedOutTheListShowsTheModelsThatCanBeRoutedAndHidesTheOnesThatCannot() {
        let all = [
            cloudModel("openai/mini", usable: false), cloudModel("anthropic/sonnet", usable: false),
            cloudModel("vendor/off", availability: .disabled, usable: false),
        ]
        let list = CloudListLogic.arrange(
            models: all, query: "", sort: .topUsage, usageRank: [:], showUnusable: false, signedIn: false)
        #expect(Set(list.rest.map(\.id)) == ["anyrouter/openai/mini", "anyrouter/anthropic/sonnet"])
        let searched = CloudListLogic.arrange(
            models: all, query: "sonnet", sort: .topUsage, usageRank: [:], showUnusable: false, signedIn: false)
        #expect(searched.rest.map(\.id) == ["anyrouter/anthropic/sonnet"])
    }

    @Test func signedInStillHidesWhatNeedsAKey() {
        let all = [cloudModel("openai/mini"), cloudModel("anthropic/sonnet", availability: .needsKey, usable: true)]
        let list = CloudListLogic.arrange(models: all, query: "", sort: .topUsage, usageRank: [:], showUnusable: true)
        #expect(list.rest.map(\.id) == ["anyrouter/openai/mini"])
    }

    // MARK: tapping

    @Test func tappingACloudModelSignedOutOpensTheSignInSheet() {
        let model = cloudModel("openai/mini", usable: false)
        #expect(CloudSignInLogic.tap(model, signedIn: false) == .signIn)
        #expect(CloudSignInLogic.tap(cloudModel("openai/mini"), signedIn: true) == .select)
        #expect(CloudSignInLogic.tap(cloudModel("a/b", availability: .needsKey, usable: true), signedIn: true) == .explainKey)
        #expect(CloudSignInLogic.tap(cloudModel("a/b", availability: .disabled, usable: true), signedIn: true) == .ignore)
        #expect(CloudSignInLogic.tap(testModel(), signedIn: false) == .select, "on-device models never ask for sign-in")
    }

    // MARK: signing in from the sheet

    @Test func aGoodSignInPicksTheTappedModel() async throws {
        let r = await rig()
        #expect(!r.tapped.isInstalled)
        let outcome = try await CloudSignInLogic.signIn(mode: .signIn, then: r.tapped, account: r.account, models: r.models)
        guard case .selected(let picked) = outcome else { Issue.record("expected a pick, got \(outcome)"); return }
        #expect(picked.id == r.tapped.id)
        #expect(picked.isInstalled, "the pick comes from the list reloaded with the new key")
        #expect(r.account.modes == [.signIn])
    }

    @Test func createAccountUsesTheSignUpFlow() async throws {
        let r = await rig()
        _ = try await CloudSignInLogic.signIn(mode: .signUp, then: r.tapped, account: r.account, models: r.models)
        #expect(r.account.modes == [.signUp])
    }

    @Test func closingTheSignInWindowLeavesTheSheetOpen() async throws {
        let r = await rig()
        r.account.behavior = .cancels
        let outcome = try await CloudSignInLogic.signIn(mode: .signIn, then: r.tapped, account: r.account, models: r.models)
        #expect(outcome == .stillSignedOut)
    }

    @Test func aFailedSignInReportsItsReason() async {
        let r = await rig()
        r.account.behavior = .fails
        await #expect(throws: SignInTestAccount.Refused.self) {
            _ = try await CloudSignInLogic.signIn(mode: .signIn, then: r.tapped, account: r.account, models: r.models)
        }
    }

    @Test func aModelThatNeedsAKeyIsNotPickedAfterSignIn() async throws {
        let r = await rig(needsKey: true)
        let outcome = try await CloudSignInLogic.signIn(mode: .signIn, then: r.tapped, account: r.account, models: r.models)
        #expect(outcome == .signedInOnly)
    }
}
