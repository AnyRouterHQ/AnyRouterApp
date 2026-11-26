import SwiftUI
import Testing
import UIKit
@testable import AnyRouter

struct AccentForegroundTests {
    private func rgb(_ name: String, dark: Bool) throws -> (Double, Double, Double) {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let color = try #require(UIColor(named: name, in: Bundle(for: AppState.self), compatibleWith: traits))
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The label of a prominent button sits on the accent. With the mono accent that is black in light mode and white in
    /// dark mode, so the label must be the other way round in each.
    @Test func theProminentLabelKeepsContrastOnTheAccentInBothModes() throws {
        for dark in [false, true] {
            let ratio = contrast(try rgb("AccentForeground", dark: dark), try rgb("AccentColor", dark: dark))
            #expect(ratio >= 7, "dark: \(dark), contrast \(ratio)")
        }
    }

    @Test func theLabelIsLightOnTheDarkAccentAndDarkOnTheLightAccent() throws {
        #expect(luminance(try rgb("AccentForeground", dark: false)) > luminance(try rgb("AccentColor", dark: false)))
        #expect(luminance(try rgb("AccentForeground", dark: true)) < luminance(try rgb("AccentColor", dark: true)))
    }
}
