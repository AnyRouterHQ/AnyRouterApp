import Foundation
import Testing
@testable import AnyRouter

/// Which model a chat gets when nobody picked one. The matrix is signed in or out, Apple available
/// or not, a local model installed or not, and a saved pick that is valid or not.
struct DefaultModelPolicyTests {
    private func cloud(_ wire: String, usable: Bool) -> ModelDescriptor {
        ModelDescriptor(id: "anyrouter/\(wire)", source: .anyrouter, displayName: wire, contextLength: nil,
                        capabilities: ["chat"], sizeBytes: nil, isInstalled: usable)
    }

    /// The model list as the registry returns it for one combination.
    private func world(signedIn: Bool, apple: Bool, local: Bool) -> [ModelDescriptor] {
        [
            cloud("anyrouter/byok", usable: signedIn),
            cloud("anyrouter/coding", usable: signedIn),
            cloud("anyrouter/auto", usable: signedIn),
            cloud("openai/gpt-5", usable: signedIn),
            testModel(id: "apple/foundation", source: .apple, installed: apple),
            testModel(id: "gguf/org/m/m.gguf", source: .gguf, installed: local),
        ]
    }

    private func pick(saved: String? = nil, signedIn: Bool, apple: Bool, local: Bool) -> String? {
        DefaultModelPolicy.resolve(saved: saved, models: world(signedIn: signedIn, apple: apple, local: local))?.id
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func signedInDefaultsToAutoNoMatterWhatElseExists(apple: Bool, local: Bool) {
        #expect(pick(signedIn: true, apple: apple, local: local) == "anyrouter/anyrouter/auto")
    }

    @Test func signedOutPrefersAppleWhenAvailable() {
        #expect(pick(signedIn: false, apple: true, local: true) == "apple/foundation")
        #expect(pick(signedIn: false, apple: true, local: false) == "apple/foundation")
    }

    @Test func signedOutWithoutAppleUsesTheFirstInstalledLocalModel() {
        #expect(pick(signedIn: false, apple: false, local: true) == "gguf/org/m/m.gguf")
    }

    @Test func nothingUsableMeansNoDefault() {
        #expect(pick(signedIn: false, apple: false, local: false) == nil)
    }

    @Test func aValidSavedPickWinsOverThePolicy() {
        #expect(pick(saved: "apple/foundation", signedIn: true, apple: true, local: true) == "apple/foundation")
        #expect(pick(saved: "gguf/org/m/m.gguf", signedIn: true, apple: true, local: true) == "gguf/org/m/m.gguf")
    }

    @Test func aSavedBYOKPickIsRespectedBecauseTheUserChoseIt() {
        #expect(pick(saved: "anyrouter/anyrouter/byok", signedIn: true, apple: true, local: true) == "anyrouter/anyrouter/byok")
    }

    @Test func anInvalidSavedPickFallsBackToThePolicy() {
        // Deleted model.
        #expect(pick(saved: "gguf/gone/m.gguf", signedIn: true, apple: true, local: true) == "anyrouter/anyrouter/auto")
        // Cloud pick after signing out.
        #expect(pick(saved: "anyrouter/openai/gpt-5", signedIn: false, apple: true, local: true) == "apple/foundation")
        // Local pick that is no longer installed.
        #expect(pick(saved: "gguf/org/m/m.gguf", signedIn: false, apple: false, local: false) == nil)
    }

    @Test func byokIsNeverTheDefaultEvenWhenItIsTheOnlyCloudModel() {
        let onlyByok = [cloud("anyrouter/byok", usable: true), testModel(id: "apple/foundation", source: .apple, installed: false)]
        #expect(DefaultModelPolicy.resolve(saved: nil, models: onlyByok) == nil)
        let withCoding = onlyByok + [cloud("anyrouter/coding", usable: true)]
        #expect(DefaultModelPolicy.resolve(saved: nil, models: withCoding)?.id == "anyrouter/anyrouter/coding")
    }

    // MARK: Fallback note

    @Test func noNoteWithoutASavedDefaultOrWhileItStillWorks() {
        let models = world(signedIn: true, apple: true, local: true)
        #expect(DefaultModelPolicy.fallbackNote(saved: nil, models: models) == nil)
        #expect(DefaultModelPolicy.fallbackNote(saved: "apple/foundation", models: models) == nil)
    }

    @Test func aDefaultThatCannotBeUsedNamesItAndTheModelThatTookOver() {
        // Signed out: the saved cloud model is listed but not usable, Apple Intelligence takes over.
        let models = world(signedIn: false, apple: true, local: true)
        #expect(DefaultModelPolicy.fallbackNote(saved: "anyrouter/openai/gpt-5", models: models)
            == "Your default model, openai/gpt-5, is not available. New chats use apple/foundation.")
    }

    @Test func aDeletedDefaultIsNamedByItsFileAndAutoTakesOverWhenSignedIn() {
        let models = world(signedIn: true, apple: true, local: true)
        #expect(DefaultModelPolicy.fallbackNote(saved: "gguf/gone/model-q4.gguf", models: models)
            == "Your default model, model-q4.gguf, is not available. New chats use AnyRouter.")
    }

    @Test func withNothingUsableTheNoteAsksForAnotherDefault() {
        let models = world(signedIn: false, apple: false, local: false)
        #expect(DefaultModelPolicy.fallbackNote(saved: "gguf/org/m/m.gguf", models: models)
            == "Your default model, gguf/org/m/m.gguf, is not available. Choose another default.")
    }
}
