import SwiftUI

/// Liquid Glass for navigation and controls only; content stays flat in token colors (D15).
/// With Reduce Transparency on, the surface is a solid token color with a hairline border.
struct ARGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(ARColor.card, in: shape)
                .overlay(shape.strokeBorder(ARColor.border, lineWidth: 1))
        } else if interactive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    func arGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ARGlass(shape: shape, interactive: interactive))
    }
}
