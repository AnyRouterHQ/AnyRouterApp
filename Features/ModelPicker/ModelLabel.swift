import SwiftUI

/// A model's logo at the size of the text next to it. Scales with Dynamic Type.
struct ModelLogo: View {
    let brand: ModelBrand
    var size: CGFloat

    var body: some View {
        Group {
            switch brand {
            case .asset(let name):
                Image(name).resizable().renderingMode(.template).scaledToFit()
            case .symbol(let name):
                Image(systemName: name).resizable().scaledToFit()
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
}

/// The one way to show a model name: logo and name together.
struct ModelLabel: View {
    enum Style { case row, pill, inline }

    let name: String
    let brand: ModelBrand
    var style: Style = .row

    @ScaledMetric(relativeTo: .body) private var rowSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var pillSize: CGFloat = 16
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
        case .pill: pillSize
        case .inline: inlineSize
        }
    }

    private var font: Font {
        switch style {
        case .row: .body
        case .pill: .subheadline.weight(.medium)
        case .inline: .footnote
        }
    }
}
