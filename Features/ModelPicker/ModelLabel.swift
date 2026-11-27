import SwiftUI

/// A model's logo at the size of the text next to it. Scales with Dynamic Type.
struct ModelLogo: View {
    let brand: ModelBrand
    var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch brand {
            case .asset(let name):
                if let color = ModelBrand.colorAsset(for: name, dark: colorScheme == .dark) {
                    asset(color, template: false)
                } else {
                    asset(name, template: true)
                }
            case .symbol(let name):
                Image(systemName: name).resizable().scaledToFit()
            case .tile(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: size * 0.22))
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().renderingMode(.template).scaledToFit()
                    } else {
                        Image(systemName: "cube").resizable().scaledToFit()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityIdentifier("model-logo")
    }

    /// Drawn at `size`, so a picker or menu that drops the frame still shows it in the icon slot.
    private func asset(_ name: String, template: Bool) -> some View {
        let image = LogoImage.make(name, side: size, template: template).map(Image.init(uiImage:)) ?? Image(name)
        return image.resizable().renderingMode(template ? .template : .original).scaledToFit()
    }
}

/// The one way to show a model name: logo and name together.
struct ModelLabel: View {
    enum Style { case row, inline }

    let name: String
    let brand: ModelBrand
    var style: Style = .row

    @ScaledMetric(relativeTo: .body) private var rowSize: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) private var inlineSize: CGFloat = 13

    init(name: String, brand: ModelBrand, style: Style = .row) {
        self.name = name
        self.brand = brand
        self.style = style
    }

    init(model: ModelDescriptor, style: Style = .row) {
        self.init(name: model.shortName, brand: ModelBrand.resolve(model), style: style)
    }

    var body: some View {
        HStack(spacing: style == .row ? 12 : 6) {
            ModelLogo(brand: brand, size: size)
            Text(name).font(font).lineLimit(1)
        }
    }

    private var size: CGFloat {
        switch style {
        case .row: rowSize
        case .inline: inlineSize
        }
    }

    private var font: Font {
        switch style {
        case .row: .body
        case .inline: .footnote
        }
    }
}
