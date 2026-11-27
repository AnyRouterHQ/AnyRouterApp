import Testing
@testable import AnyRouter

struct SettingsDestinationTests {
    @Test func everyDestinationIsListedOnceInTheRootOrAbout() {
        let listed = SettingsDestination.Group.allCases.flatMap(\.destinations) + SettingsDestination.aboutPages
        #expect(Set(listed) == Set(SettingsDestination.allCases))
        #expect(listed.count == SettingsDestination.allCases.count)
    }

    @Test func rootRowsAndTheirOrderFitOneScreen() {
        let rows = SettingsDestination.Group.allCases.map { group in (group.title, group.destinations.map(\.title)) }
        #expect(rows.map(\.0) == ["Models", "Chat", "App"])
        #expect(rows[0].1 == ["Local Models", "AnyRouter Models"])
        #expect(rows[1].1 == ["Responses", "Presets", "Integrations", "Chat Behavior"])
        #expect(rows[2].1 == ["Shortcuts & Controls", "Theme", "Privacy", "About"])
        #expect(rows.flatMap(\.1).count <= 10, "the root list stays short enough for one iPhone screen")
    }

    @Test func aboutHoldsDiagnosticsTermsAndLicenses() {
        #expect(SettingsDestination.aboutPages == [.diagnostics, .terms, .licenses])
        for page in SettingsDestination.aboutPages { #expect(page.group == nil) }
        #expect(SettingsDestination.about.group == .app)
        #expect(SettingsDestination.chatBehavior.group == .chat)
    }

    @Test func modelsComeFirstAsLocalThenAnyRouter() {
        #expect(SettingsDestination.localModels.title == "Local Models")
        #expect(SettingsDestination.anyRouterModels.title == "AnyRouter Models")
        #expect(SettingsDestination.responseCustomization.title == "Responses")
        #expect(SettingsDestination.localModels.group == .models)
        #expect(SettingsDestination.presets.group == .chat)
    }

    @Test func shortcutsPageNamesEveryEntryPointWithHowToAddIt() {
        let titles = ShortcutsLogic.features.map(\.title)
        #expect(titles == ["Siri and Shortcuts", "Control Center and Lock Screen", "Action Button", "Share sheet", "Read text from a photo"])
        for feature in ShortcutsLogic.features {
            #expect(!feature.summary.isEmpty && !feature.howToAdd.isEmpty && !feature.symbol.isEmpty)
            #expect(feature.id == feature.title)
        }
    }

    @Test func titlesAndIconsAreFilled() {
        for destination in SettingsDestination.allCases {
            #expect(!destination.title.isEmpty)
            #expect(!destination.systemImage.isEmpty)
        }
    }

    @Test func anyRouterModelsShowsTheAnyRouterMarkAndOtherPagesTheirSymbol() {
        #expect(SettingsDestination.anyRouterModels.glyph == .asset(ModelBrand.anyRouterMark))
        #expect(SettingsDestination.localModels.glyph == .symbol("cube"))
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
