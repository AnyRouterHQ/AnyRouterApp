import Foundation
import Testing
@testable import AnyRouter

/// Apple Intelligence on Private Cloud Compute (iOS 27): every status the framework or the signature can give becomes
/// the picker row and the Not available reason; its errors become words. Tested without the iOS 27 SDK.
struct ApplePCCLogicTests {
    @Test func eachStatusHasItsReasonAndOnlyAvailableHasNone() {
        #expect(ApplePCCLogic.reason(.available(contextSize: 32_768)) == nil)
        #expect(ApplePCCLogic.reason(.deviceNotEligible) == "This device does not support Apple Intelligence")
        #expect(ApplePCCLogic.reason(.systemNotReady) == "Turn on Apple Intelligence, or wait until it finishes setting up")
        #expect(ApplePCCLogic.reason(.unavailable) == "Private Cloud Compute is not available right now")
        #expect(ApplePCCLogic.reason(.needsNewerSystem) == "Needs iOS 27")
        #expect(ApplePCCLogic.reason(.notEntitled) == "This build is not yet allowed to use Private Cloud Compute")
    }

    @Test func aMissingEntitlementWinsOverTheFrameworkAndAnUnreadableSignatureDoesNot() {
        #expect(ApplePCCLogic.status(framework: .available(contextSize: 32_768), entitled: false) == .notEntitled)
        #expect(ApplePCCLogic.status(framework: .available(contextSize: 32_768), entitled: true) == .available(contextSize: 32_768))
        #expect(ApplePCCLogic.status(framework: .systemNotReady, entitled: nil) == .systemNotReady)
    }

    @Test func theDescriptorCarriesTheContextTheFrameworkReports() {
        let ready = ApplePCCLogic.descriptor(.available(contextSize: 32_768))
        #expect(ready.id == "apple/pcc" && ready.source == .apple && ready.displayName == "Apple Intelligence (Cloud)")
        #expect(ready.contextLength == 32_768 && ready.isInstalled && ready.summary == nil)
        #expect(ready.capabilities == ["chat", "tools"])
        let off = ApplePCCLogic.descriptor(.deviceNotEligible)
        #expect(!off.isInstalled && off.contextLength == nil && off.capabilities == ["chat"])
        #expect(off.summary == "This device does not support Apple Intelligence")
    }

    @Test func theContextReadsInThousands() {
        #expect(ApplePCCLogic.contextText(32_768) == "32K context")
        #expect(ApplePCCLogic.contextText(nil) == nil)
    }

    @Test func eachFailureHasWordsThatSayWhatToDo() {
        #expect(ApplePCCLogic.text(.quotaLimitReached).hasPrefix("You reached today's Private Cloud Compute limit."))
        #expect(ApplePCCLogic.text(.networkFailure).hasPrefix("Private Cloud Compute needs the internet."))
        #expect(ApplePCCLogic.text(.serviceUnavailable) == "Private Cloud Compute is busy. Try again in a moment.")
    }
}

/// The Apple engine lists the cloud model next to the on-device one and refuses a request with the exact reason.
@MainActor
struct ApplePCCEngineTests {
    private struct Stub: ApplePCCProbing {
        let value: ApplePCCStatus
        func status() async -> ApplePCCStatus { value }
    }

    /// Agent v2 U3: the on-device window is what the system reports, not a hard-coded 4,096. It feeds the compaction
    /// window and the prompt budget.
    @Test func theOnDeviceWindowComesFromTheSystem() async throws {
        let engine = AppleFoundationEngine(pcc: Stub(value: .needsNewerSystem), onDeviceContextSize: { 8192 })
        let onDevice = try #require(try await engine.availableModels().first)
        #expect(onDevice.id == "apple/foundation" && onDevice.contextLength == 8192)
        #expect(CompactionLogic.window(for: onDevice) == 8192)
    }

    @Test func theEngineListsTheCloudModelAfterTheOnDeviceOne() async throws {
        let models = try await AppleFoundationEngine(pcc: Stub(value: .available(contextSize: 32_768))).availableModels()
        #expect(models.map(\.id) == ["apple/foundation", "apple/pcc"])
        #expect(models.last == ApplePCCLogic.descriptor(.available(contextSize: 32_768)))
    }

    @Test func aRequestToAnUnavailableCloudModelStopsWithItsReason() async {
        let engine = AppleFoundationEngine(pcc: Stub(value: .needsNewerSystem))
        let stream = engine.stream(
            model: ApplePCCLogic.descriptor(.needsNewerSystem),
            messages: [ChatMessage(role: .user, content: "Hello")], params: GenerationParams())
        do {
            for try await _ in stream {}
            Issue.record("expected the request to stop")
        } catch {
            #expect(error.localizedDescription == "Needs iOS 27")
        }
    }
}
