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
