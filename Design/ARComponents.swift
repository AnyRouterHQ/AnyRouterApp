import SwiftUI

/// Brand mark (template image, tinted by the foreground style). The logo is part of the brand, so it stays custom.
struct ARLogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("BrandMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Muted section caption ("Installed Models", "Pinned").
struct ARSectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ARColor.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
