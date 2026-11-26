import SwiftUI
import UIKit

/// Color tokens ported from Atomic Chat `web-app/src/index.css` (`:root` and `.dark`, oklch converted to sRGB).
/// Brand accent comes from anyrouter.dev.
enum ARColor {
    static let background = dynamic(light: 0xFFFFFF, dark: 0x121212)
    static let foreground = dynamic(light: 0x0A0A0A, dark: 0xFAFAFA)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let popover = dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let primary = dynamic(light: 0x171717, dark: 0xE5E5E5)
    static let primaryForeground = dynamic(light: 0xFAFAFA, dark: 0x171717)
    static let secondary = dynamic(light: 0xF5F5F5, dark: 0x383838)
    static let muted = dynamic(light: 0xF5F5F5, dark: 0x333333)
    static let mutedForeground = dynamic(light: 0x737373, dark: 0xB7B7B7)
    static let destructive = dynamic(light: 0xE7000B, dark: 0xFF6467)
    static let border = dynamic(light: 0xE5E5E5, dark: 0xFFFFFF, darkAlpha: 0.14)
    static let input = dynamic(light: 0xE5E5E5, dark: 0xFFFFFF, darkAlpha: 0.18)
    static let ring = dynamic(light: 0xA1A1A1, dark: 0xA4A4A4)
    static let sidebar = dynamic(light: 0xF2F2F2, dark: 0x1B1B1B)
    static let sidebarAccent = dynamic(light: 0xF5F5F5, dark: 0x262626)
    /// AnyRouter brand accent.
    static let accent = dynamic(light: 0xBB4D00, dark: 0xE87D45)
    static let accentForeground = dynamic(light: 0xFFFBEB, dark: 0x461901)

    private static func dynamic(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: 1)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
