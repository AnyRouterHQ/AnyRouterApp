import Foundation
import Testing
@testable import AnyRouter

/// Which model a mini app runs: the person's pick, then the app's preferred and fallback models, and only models that
/// meet the app's requirement and can run now.
struct MiniAppModelChoiceTests {
    private let apple = testModel(id: "apple/foundation")
    private let auto = testModel(id: "anyrouter/anyrouter/auto", source: .anyrouter)
    private let free = testDecision("anyrouter/decision")
    private let sees = testDecision("google/gemini-decision-1", vision: true)

    private func choose(
        _ ids: [String?], requirement: ModelRequirement, chat: [ModelDescriptor] = [], decision: [ModelDescriptor] = []
    ) -> ModelDescriptor? {
        MiniAppModelChoice.choose(ids, from: requirement.models(chat: chat, decision: decision))
    }

    @Test func thePersonsPickWinsOverTheAppsModels() {
        let pick = choose(["google/gemini-decision-1", "anyrouter/decision"], requirement: .decision(needsVision: false), decision: [free, sees])
        #expect(pick == sees)
    }

    @Test func aMissingPreferredModelFallsToTheFallback() {
        let pick = choose([nil, "x/gone", "anyrouter/decision"], requirement: .decision(needsVision: false), decision: [sees, free])
        #expect(pick == free)
    }

    @Test func withNeitherListedTheFirstModelThatRunsIsUsed() {
        #expect(choose(["x/gone", "y/gone"], requirement: .decision(needsVision: false), decision: [sees, free]) == sees)
    }

    /// Signed out no cloud model is usable: Decisions has nothing to run, Extract runs on the device.
    @Test func signedOutDecisionsHaveNoModelAndExtractUsesTheDevice() {
        var lockedDecision = free
        lockedDecision.isInstalled = false
        var lockedAuto = auto
        lockedAuto.isInstalled = false
        #expect(choose(["anyrouter/decision"], requirement: .decision(needsVision: false), decision: [lockedDecision]) == nil)
        #expect(choose(["anyrouter/auto", "apple/foundation"], requirement: .chat, chat: [lockedAuto, apple]) == apple)
    }

    /// A photo is attached and no model reads photos: nothing is chosen, so Run asks for a model.
    @Test func aPhotoWithNoVisionModelChoosesNothing() {
        #expect(choose(["anyrouter/decision"], requirement: .decision(needsVision: true), decision: [free]) == nil)
    }

    /// A text-only pick is skipped while a photo is attached, not replaced.
    @Test func aPickThatCannotReadThePhotoIsSkipped() {
        let ids = ["anyrouter/decision", "google/gemini-decision-1"]
        #expect(choose(ids, requirement: .decision(needsVision: true), decision: [free, sees]) == sees)
        #expect(choose(ids, requirement: .decision(needsVision: false), decision: [free, sees]) == free)
    }

    /// The chat's requirement keeps the chat's list exactly; a decision requirement never offers a chat or local model.
    @Test func theChatRequirementListsEveryChatModelAndDecisionsOnlyDecisionModels() {
        let requirement = ModelRequirement.chat
        #expect(requirement.models(chat: [apple, auto], decision: [free]) == [apple, auto])
        #expect(requirement.allowsLocal)
        #expect(ModelRequirement.decision(needsVision: false).models(chat: [apple, auto], decision: [free, sees]) == [free, sees])
        #expect(ModelRequirement.decision(needsVision: true).models(chat: [], decision: [free, sees]) == [sees])
        #expect(!ModelRequirement.decision(needsVision: false).allowsLocal)
    }

    @Test func picksAreSavedPerAppAsWireIDs() {
        let picks = MiniAppModelPicks(defaults: testDefaults())
        picks.remember(sees, for: "decisions.traffic-sign")
        #expect(picks.pick(for: "decisions.traffic-sign") == "google/gemini-decision-1")
        #expect(picks.pick(for: "extract") == nil)
    }
}
