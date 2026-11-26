import Testing
@testable import AnyRouter

struct SettingsDestinationTests {
    @Test func everyDestinationIsListedInExactlyOneGroup() {
        let listed = SettingsDestination.Group.allCases.flatMap(\.destinations)
        #expect(Set(listed) == Set(SettingsDestination.allCases))
        #expect(listed.count == SettingsDestination.allCases.count)
    }

    @Test func groupsAreOrderedModelsChatAppearanceAbout() {
        #expect(SettingsDestination.Group.allCases.map(\.title) == ["Models", "Chat", "Appearance", "About"])
    }

    @Test func routingTableMatchesTheSpec() {
        #expect(SettingsDestination.Group.models.destinations == [.manageModels, .defaultModel, .inference, .catalogSources])
        #expect(SettingsDestination.Group.chat.destinations == [.presets, .integrations])
        #expect(SettingsDestination.Group.about.destinations == [.diagnostics, .privacy, .terms, .licenses])
        #expect(SettingsDestination.presets.group == .chat)
        #expect(SettingsDestination.theme.group == .appearance)
    }

    @Test func titlesAndIconsAreFilled() {
        for destination in SettingsDestination.allCases {
            #expect(!destination.title.isEmpty)
            #expect(!destination.systemImage.isEmpty)
        }
    }

    @Test func versionAndDiagnosticsText() {
        #expect(SettingsLogic.versionText(version: "1.2", build: "7") == "1.2 (7)")
        #expect(SettingsLogic.versionText(version: "1.2", build: "7", commit: "abc1234") == "1.2 (7) · abc1234")
        #expect(SettingsLogic.versionText(version: "1.2", build: "7", commit: "") == "1.2 (7)")
        let text = SettingsLogic.diagnostics(version: "1.2", build: "7", system: "26.0")
        #expect(text == "AnyRouter 1.2 (7) · \(SettingsLogic.appCommit)\niOS 26.0")
        #expect(SettingsLogic.diagnosticsTapCount == 7)
    }
}
