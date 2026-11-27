import Testing
import UIKit
@testable import AnyRouter

@MainActor
struct LogoImageTests {
    /// The brand mark is a large vector; a picker that drops the frame showed it at that size across the whole sheet.
    @Test func aLogoIsDrawnAtTheSlotSizeWhateverItsAssetSize() throws {
        let source = try #require(UIImage(named: ModelBrand.anyRouterMark))
        #expect(max(source.size.width, source.size.height) > 22, "the asset is larger than the slot, or this test proves nothing")
        let logo = try #require(LogoImage.make(ModelBrand.anyRouterMark, side: 22, template: true))
        #expect(abs(max(logo.size.width, logo.size.height) - 22) < 0.5)
        #expect(logo.renderingMode == .alwaysTemplate)
        #expect(LogoImage.make(ModelBrand.anyRouterMark, side: 22, template: false)?.renderingMode == .alwaysOriginal)
        #expect(LogoImage.make(ModelBrand.anyRouterMark, side: 22, template: true) === logo, "drawn once per size")
    }

    @Test func anUnknownNameHasNoImage() {
        #expect(LogoImage.make("no-such-logo", side: 22, template: true) == nil)
    }
}
