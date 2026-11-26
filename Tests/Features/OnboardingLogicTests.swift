import Foundation
import Testing
@testable import AnyRouter

struct OnboardingLogicTests {
    private func entry(_ id: String, size: Int64?, fit: ModelFit = .fits) -> LocalModelEntry {
        var descriptor = testModel(id: id, source: .gguf)
        descriptor.sizeBytes = size
        return LocalModelEntry(descriptor: descriptor, summary: "", tags: [], fit: fit, isUserAdded: false)
    }

    @Test func recommendsFirstSmallModelThatFits() {
        let catalog = [entry("huge", size: 9_000_000_000), entry("small", size: 700_000_000), entry("tiny", size: 300_000_000)]
        #expect(OnboardingLogic.recommendedLocal(in: catalog)?.id == "small")
    }

    @Test func aCatalogFlaggedModelComesFirstEvenWhenAnEarlierOneIsSmaller() {
        var flagged = entry("flagged", size: 1_200_000_000)
        flagged.isOnboarding = true
        let catalog = [entry("tiny", size: 300_000_000), flagged]
        #expect(OnboardingLogic.recommendedLocal(in: catalog)?.id == "flagged")
        flagged.fit = .wontFit
        #expect(OnboardingLogic.recommendedLocal(in: [entry("tiny", size: 300_000_000), flagged])?.id == "tiny", "a flagged model that will not fit is skipped")
    }

    @Test func skipsModelsThatWillNotFit() {
        let catalog = [entry("big-no", size: 500_000_000, fit: .wontFit), entry("ok", size: 800_000_000)]
        #expect(OnboardingLogic.recommendedLocal(in: catalog)?.id == "ok")
    }

    @Test func skipsModelsThatCannotRunOnThisDevice() {
        var mlx = entry("mlx", size: 400_000_000)
        mlx.unavailableReason = "MLX needs a GPU"
        let catalog = [mlx, entry("gguf", size: 900_000_000)]
        #expect(OnboardingLogic.recommendedLocal(in: catalog)?.id == "gguf")
    }

    @Test func fallsBackToSmallestWhenNothingIsSmall() {
        let catalog = [entry("b", size: 4_000_000_000), entry("a", size: 2_000_000_000)]
        #expect(OnboardingLogic.recommendedLocal(in: catalog)?.id == "a")
        #expect(OnboardingLogic.recommendedLocal(in: []) == nil)
    }

    @Test func canFinishOnlyWhenTheChoiceWorks() {
        func can(_ c: OnboardingLogic.Choice?, apple: Bool = false, local: DownloadState = .notInstalled, signedIn: Bool = false) -> Bool {
            OnboardingLogic.canFinish(choice: c, appleAvailable: apple, localState: local, signedIn: signedIn)
        }
        #expect(!can(nil, apple: true, signedIn: true))
        #expect(can(.apple, apple: true))
        #expect(!can(.apple))
        #expect(!can(.local, local: .downloading(progress: 0.5)))
        #expect(can(.local, local: .installed))
        #expect(!can(.cloud))
        #expect(can(.cloud, signedIn: true))
    }

    @Test func modelIDFollowsTheChoice() {
        let models = [testModel(id: "apple/foundation", source: .apple), testModel(id: "anyrouter/x/y", source: .anyrouter)]
        let local = entry("gguf/org/m/f.gguf", size: 1)
        #expect(OnboardingLogic.modelID(for: .apple, models: models, local: local) == "apple/foundation")
        #expect(OnboardingLogic.modelID(for: .cloud, models: models, local: local) == "anyrouter/x/y")
        #expect(OnboardingLogic.modelID(for: .local, models: models, local: local) == "gguf/org/m/f.gguf")
    }
}
