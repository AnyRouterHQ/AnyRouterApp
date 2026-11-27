import SwiftUI
import Testing
@testable import AnyRouter

struct ReplyTextTests {
    @Test func theDefaultStepIsTheSystemSize() {
        #expect(ReplyText.scale(step: ReplyText.defaultStep) == 1)
        #expect(ReplyText.points(17, step: 0) == 17)
    }

    @Test func eachStepScalesTheSystemSizeInTheSameDirection() {
        #expect(ReplyText.points(17, step: -2) == 15)
        #expect(ReplyText.points(17, step: 1) == 18)
        #expect(ReplyText.points(17, step: 3) == 20)
        #expect(abs(ReplyText.scale(step: 3) - 1.18) < 1e-9)
        let sizes = ReplyText.steps.map { ReplyText.points(17, step: $0) }
        #expect(sizes == sizes.sorted(), "a larger step never makes the text smaller")
    }

    @Test func aStepOutsideTheRangeIsHeldAtTheEdge() {
        #expect(ReplyText.clamped(-9) == -2)
        #expect(ReplyText.clamped(9) == 3)
        #expect(ReplyText.clamped(2) == 2)
        #expect(ReplyText.scale(step: 99) == ReplyText.scale(step: 3))
    }

    @Test func theLabelReadsDefaultOrASignedNumber() {
        #expect(ReplyText.label(step: 0) == "Default")
        #expect(ReplyText.label(step: 2) == "+2")
        #expect(ReplyText.label(step: -1) == "-1")
        #expect(ReplyText.label(step: 40) == "+3")
    }

    @Test func eachFontMapsToItsSystemDesign() {
        #expect(ReplyFont.system.design == .default)
        #expect(ReplyFont.serif.design == .serif)
        #expect(ReplyFont.rounded.design == .rounded)
        #expect(ReplyFont.allCases.map(\.title) == ["System", "Serif", "Rounded"])
        #expect(ReplyFont.serif.id == "serif")
    }

    @Test func thePreviewIsReadAsOneLineAboutTheChoice() {
        #expect(ReplyText.previewLabel(step: 0, font: .system) == "Preview of a reply, text size default, system font")
        #expect(ReplyText.previewLabel(step: 2, font: .serif) == "Preview of a reply, text size +2, serif font")
    }
}

@MainActor
struct ReplyTextSettingsTests {
    @Test func repliesStartAtTheSystemSizeInTheSystemFont() {
        let settings = AppSettings(defaults: testDefaults())
        #expect(settings.replyTextStep == 0)
        #expect(settings.replyFont == .system)
    }

    @Test func theChoiceSurvivesARelaunch() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.replyTextStep = 2
        settings.replyFont = .rounded
        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.replyTextStep == 2)
        #expect(relaunched.replyFont == .rounded)
    }

    @Test func aStepOutsideTheRangeIsStoredAtTheEdge() {
        let settings = AppSettings(defaults: testDefaults())
        settings.replyTextStep = 12
        #expect(settings.replyTextStep == 3)
        settings.replyTextStep = -12
        #expect(settings.replyTextStep == -2)
    }

    @Test func anOldOrBrokenStoredValueFallsBackToTheDefaults() {
        let defaults = testDefaults()
        defaults.set(50, forKey: "settings.replyTextStep")
        defaults.set("comic-sans", forKey: "settings.replyFont")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.replyTextStep == 3)
        #expect(settings.replyFont == .system)
    }
}
