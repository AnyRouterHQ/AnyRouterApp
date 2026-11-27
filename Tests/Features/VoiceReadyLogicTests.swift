import Foundation
import Testing
@testable import AnyRouter

struct VoiceReadyLogicTests {
    @Test func inFrontItIsABannerWhateverTheNotificationSetting() {
        for permission in [VoiceReadyLogic.Permission.notDetermined, .granted, .denied] {
            #expect(VoiceReadyLogic.announcement(appIsActive: true, permission: permission) == .banner)
        }
    }

    @Test func awayItIsOneNotificationOnlyWhenAllowed() {
        #expect(VoiceReadyLogic.announcement(appIsActive: false, permission: .granted) == .notification)
        #expect(VoiceReadyLogic.announcement(appIsActive: false, permission: .denied) == .nothing)
        #expect(VoiceReadyLogic.announcement(appIsActive: false, permission: .notDetermined) == .nothing,
                "no prompt appears to an app that is away, so nothing is sent")
    }

    @Test func thePermissionIsAskedOnlyOnceTheAnswerIsOpen() {
        #expect(VoiceReadyLogic.shouldAsk(.notDetermined))
        #expect(!VoiceReadyLogic.shouldAsk(.granted))
        #expect(!VoiceReadyLogic.shouldAsk(.denied))
    }

    @Test func theNotificationNamesTheModelWhenItKnowsIt() {
        #expect(VoiceReadyLogic.notificationBody(modelTitle: "Whisper Base") == "Whisper Base is on your phone. Tap to start.")
        #expect(VoiceReadyLogic.notificationBody(modelTitle: nil) == "Tap to start.")
        #expect(VoiceReadyLogic.title == "Voice Mode is ready")
    }
}
