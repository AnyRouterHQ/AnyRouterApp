import SwiftUI

/// The icon tile of a Settings row, drawn like the system Settings app: a white glyph on a 29 pt rounded square of one
/// system color, the symbol at the body size (17 pt). A custom view because `Label` has no tile style; it scales with
/// Dynamic Type.
struct SettingsIcon: View {
    /// An SF Symbol, or a template image from the asset catalog (the AnyRouter mark).
    enum Glyph: Hashable, Sendable {
        case symbol(String)
        case asset(String)
    }

    let glyph: Glyph
    let color: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 29
    @ScaledMetric(relativeTo: .body) private var assetSide: CGFloat = 17

    var body: some View {
        image
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color, in: .rect(cornerRadius: side * 7 / 29))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var image: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name).font(.body.weight(.medium))
        case .asset(let name):
            Image(name).resizable().renderingMode(.template).scaledToFit().frame(width: assetSide, height: assetSide)
        }
    }
}

#Preview {
    VStack {
        SettingsIcon(glyph: .symbol("cube"), color: .green)
        SettingsIcon(glyph: .asset(ModelBrand.anyRouterMark), color: .blue)
    }
}
