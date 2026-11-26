import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct AppSettingsTests {
    @Test func defaultsMatchTheContract() {
        let p = AppSettings(defaults: testDefaults()).generationParams
        #expect(p.temperature == 0.7)
        #expect(p.topP == 0.95)
        #expect(p.maxTokens == nil)
        #expect(p.systemPrompt == nil)
    }

    @Test func zeroMaxTokensMeansUnlimitedAndBlankPromptIsDropped() {
        let s = AppSettings(defaults: testDefaults())
        s.maxTokens = 256
        s.systemPrompt = "  Be brief.  "
        #expect(s.generationParams.maxTokens == 256)
        #expect(s.generationParams.systemPrompt == "Be brief.")
        s.maxTokens = 0
        s.systemPrompt = "   "
        #expect(s.generationParams.maxTokens == nil)
        #expect(s.generationParams.systemPrompt == nil)
    }

    @Test func appearanceMapsToWindowInterfaceStyle() {
        #expect(AppSettings.Appearance.system.userInterfaceStyle == .unspecified)
        #expect(AppSettings.Appearance.light.userInterfaceStyle == .light)
        #expect(AppSettings.Appearance.dark.userInterfaceStyle == .dark)
    }

    @Test func keyboardOnLaunchIsOffByDefaultAndPersists() {
        let d = testDefaults()
        #expect(!AppSettings(defaults: d).showKeyboardOnLaunch)
        AppSettings(defaults: d).showKeyboardOnLaunch = true
        #expect(AppSettings(defaults: d).showKeyboardOnLaunch)
    }

    @Test func valuesPersistInTheirDefaults() {
        let d = testDefaults()
        AppSettings(defaults: d).temperature = 0.2
        AppSettings(defaults: d).appearance = .dark
        let reread = AppSettings(defaults: d)
        #expect(reread.temperature == 0.2)
        #expect(reread.appearance == .dark)
    }
}
