import Foundation
import Testing
@testable import AnyRouter

/// One test per reason a model can be missing from the picker's lists, plus the order of the Not available list.
struct ModelAvailabilityLogicTests {
    private func summary(balance: Double? = nil, free: Int? = nil) -> AccountSummary {
        var summary = AccountSummary()
        summary.credits = balance.map { AccountSummary.Credits(balance: $0, used: nil) }
        summary.freeRequests = free.map { AccountSummary.FreeRequests(remaining: $0, limit: 5) }
        return summary
    }

    private func fit(_ verdict: ModelFit, needed: Int64 = 12_000_000_000) -> FitDetail {
        FitDetail(
            verdict: verdict, neededBytes: needed, budgetBytes: 3_000_000_000, context: 512, maxReply: 64,
            streamsFromStorage: false, isEstimate: false)
    }

    // MARK: Cloud

    @Test func signedOutCloudModelsAskToSignIn() {
        let model = cloudModel("openai/gpt-5", usable: false)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: false) == .signIn)
        #expect(ModelUnavailableReason.signIn.text(device: "iPhone") == "Sign in to use")
        #expect(ModelUnavailableReason.signIn.fix == .signIn)
    }

    @Test func signedOutKeyModelsAskToSignInFirst() {
        let model = cloudModel("xai/grok", availability: .needsKey)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: false) == .signIn)
    }

    @Test func signedInUsableModelIsAvailable() {
        let model = cloudModel("openai/gpt-5")
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true, summary: summary(balance: 5)) == nil)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true) == nil)
    }

    @Test func aModelThatNeedsAKeyNamesTheProvider() {
        let model = cloudModel("openai/gpt-5", availability: .needsKey)
        let reason = ModelAvailabilityLogic.reason(for: model, signedIn: true)
        #expect(reason == .needsKey(provider: "OpenAI"))
        #expect(reason?.text(device: "iPhone") == "Add your own key (BYOK) for OpenAI")
        #expect(reason?.fix == .addKey)
    }

    @Test func theProviderNameFromTheCatalogWins() {
        var model = cloudModel("acme/thing", availability: .needsKey)
        model.cloud?.providerName = "Acme Labs"
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true) == .needsKey(provider: "Acme Labs"))
    }

    @Test func aKeyModelWithoutAProviderSlugStillReads() {
        var model = cloudModel("thing", availability: .needsKey)
        model.id = "anyrouter/thing"
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true) == .needsKey(provider: "this provider"))
    }

    @Test func noRouteAndDisabledAreTheirOwnReasons() {
        let none = cloudModel("a/b", availability: .noRoute)
        let off = cloudModel("a/c", availability: .disabled)
        #expect(ModelAvailabilityLogic.reason(for: none, signedIn: true) == .noRoute)
        #expect(ModelAvailabilityLogic.reason(for: off, signedIn: false) == .disabled)
        #expect(ModelUnavailableReason.noRoute.text(device: "iPhone") == "No provider is serving it right now")
        #expect(ModelUnavailableReason.disabled.text(device: "iPhone") == "Turned off")
        #expect(ModelUnavailableReason.noRoute.fix == nil)
        #expect(ModelUnavailableReason.disabled.fix == nil)
    }

    @Test func aUsableModelTheListDoesNotCallInstalledIsNotAvailable() {
        let model = cloudModel("a/b", usable: false)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true) == .noRoute)
    }

    @Test func anEmptyBalanceBlocksPaidModelsOnly() {
        let paid = cloudModel("a/paid")
        let free = cloudModel("a/free", input: 0, output: 0, billing: .free)
        let byok = cloudModel("a/byok", billing: .byok)
        let empty = summary(balance: 0)
        #expect(ModelAvailabilityLogic.reason(for: paid, signedIn: true, summary: empty) == .outOfCredits)
        #expect(ModelAvailabilityLogic.reason(for: free, signedIn: true, summary: empty) == nil)
        #expect(ModelAvailabilityLogic.reason(for: byok, signedIn: true, summary: empty) == nil)
        #expect(ModelUnavailableReason.outOfCredits.text(device: "iPhone") == "Out of credits")
        #expect(ModelUnavailableReason.outOfCredits.fix == .getCredits)
    }

    @Test func freeRequestsLeftKeepPaidModelsAvailable() {
        let paid = cloudModel("a/paid")
        #expect(ModelAvailabilityLogic.reason(for: paid, signedIn: true, summary: summary(balance: 0, free: 3)) == nil)
        #expect(ModelAvailabilityLogic.reason(for: paid, signedIn: true, summary: summary(balance: 0, free: 0)) == .outOfCredits)
    }

    @Test func anUnknownBalanceNeverBlocks() {
        let paid = cloudModel("a/paid")
        #expect(ModelAvailabilityLogic.reason(for: paid, signedIn: true, summary: summary()) == nil)
        #expect(ModelAvailabilityLogic.reason(for: paid, signedIn: true, summary: summary(balance: 4)) == nil)
    }

    @Test func aCloudModelWithoutCatalogInfoFollowsTheBalance() {
        var model = cloudModel("a/b")
        model.cloud = nil
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true, summary: summary(balance: 0)) == .outOfCredits)
    }

    // MARK: Local

    @Test func aModelThatDoesNotFitSaysHowMuchItNeeds() {
        let model = localModel("gguf/big", installed: true)
        let reason = ModelAvailabilityLogic.reason(for: model, signedIn: true, fit: fit(.wontFit))
        #expect(reason == .doesNotFit(neededBytes: 12_000_000_000))
        #expect(reason?.text(device: "iPhone") == "Doesn't fit this iPhone (needs 12.0 GB)")
        #expect(reason?.fix == .browse)
    }

    @Test func aModelThatDoesNotFitSaysSoBeforeDownloadFirst() {
        let model = localModel("gguf/big", installed: false)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true, fit: fit(.wontFit)) == .doesNotFit(neededBytes: 12_000_000_000))
    }

    @Test func aTightModelIsAvailable() {
        let model = localModel("gguf/tight")
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true, fit: fit(.tight)) == nil)
        #expect(ModelAvailabilityLogic.reason(for: model, signedIn: true, fit: fit(.fits)) == nil)
    }

    @Test func aModelNotOnTheDeviceNeedsADownload() {
        let model = localModel("gguf/later", installed: false)
        let reason = ModelAvailabilityLogic.reason(for: model, signedIn: true)
        #expect(reason == .downloadFirst)
        #expect(reason?.text(device: "iPad") == "Download first")
        #expect(reason?.fix == .browse)
        #expect(ModelUnavailableReason.Fix.browse.title == "Browse models")
    }

    @Test func anEngineNoteExplainsWhyItCannotRunHere() {
        let model = localModel("mlx/x", source: .mlx)
        let reason = ModelAvailabilityLogic.reason(for: model, signedIn: true, engineNote: "MLX needs a device")
        #expect(reason == .unsupportedHere("MLX needs a device"))
        #expect(reason?.text(device: "iPhone") == "MLX needs a device")
        #expect(reason?.fix == nil)
    }

    @Test func appleIntelligenceOffUsesItsOwnWords() {
        var apple = localModel("apple/foundation", source: .apple, installed: false)
        #expect(ModelAvailabilityLogic.reason(for: apple, signedIn: false) == .unsupportedHere(nil))
        #expect(ModelUnavailableReason.unsupportedHere(nil).text(device: "iPhone") == "Not available on this device")
        apple.summary = "Turn on Apple Intelligence in Settings"
        #expect(ModelAvailabilityLogic.reason(for: apple, signedIn: false)?.text(device: "iPhone") == "Turn on Apple Intelligence in Settings")
        apple.isInstalled = true
        #expect(ModelAvailabilityLogic.reason(for: apple, signedIn: false) == nil)
    }

    @Test func everyFixHasATitle() {
        #expect(ModelUnavailableReason.Fix.signIn.title == "Sign in")
        #expect(ModelUnavailableReason.Fix.getCredits.title == "Get credits")
        #expect(ModelUnavailableReason.Fix.addKey.title == "Add key")
    }

    // MARK: Lists

    @Test func partitionSplitsAndOrdersTheUnavailableByHowFixableTheyAre() {
        let models = [
            cloudModel("a/ok", name: "Fine"),
            cloudModel("a/off", name: "Zed off", availability: .disabled),
            cloudModel("a/key", name: "Key", availability: .needsKey),
            cloudModel("a/none", name: "Alpha none", availability: .noRoute),
            cloudModel("a/none2", name: "Beta none", availability: .noRoute),
            localModel("gguf/later", name: "Later", installed: false),
            localModel("mlx/x", name: "Mlx", source: .mlx),
            localModel("gguf/big", name: "Big"),
        ]
        let result = ModelAvailabilityLogic.partition(
            models, signedIn: true,
            fit: { $0.id == "gguf/big" ? fit(.wontFit) : nil },
            engineNote: { $0.id == "mlx/x" ? "No MLX here" : nil })
        #expect(result.available.map(\.displayName) == ["Fine"])
        #expect(result.unavailable.map(\.model.displayName) == ["Key", "Later", "Big", "Alpha none", "Beta none", "Zed off", "Mlx"])
        #expect(result.unavailable.first?.id == "anyrouter/a/key")
    }

    @Test func partitionUsesTheDefaultsWhenThereAreNoLookups() {
        let result = ModelAvailabilityLogic.partition([cloudModel("a/b")], signedIn: true)
        #expect(result.available.count == 1)
        #expect(result.unavailable.isEmpty)
    }

    @Test func localCandidatesAddCatalogModelsThatAreNotListed() {
        let installed = localModel("gguf/have", installed: true)
        let catalog = [
            entry(localModel("gguf/have", installed: true)),
            entry(localModel("gguf/new", installed: true)),
        ]
        let result = ModelAvailabilityLogic.localCandidates(listed: [installed, cloudModel("a/b")], catalog: catalog)
        #expect(result.map(\.id) == ["gguf/have", "gguf/new"])
        #expect(result[0].isInstalled)
        #expect(!result[1].isInstalled, "a catalog model that the engine does not list is not on the device")
    }

    private func entry(_ model: ModelDescriptor) -> LocalModelEntry {
        LocalModelEntry(descriptor: model, summary: "", tags: [], fit: .unknown, isUserAdded: false)
    }
}
