import SwiftUI

extension View {
    /// A floating control's glass circle. The frame sits inside the label, so the whole circle is the hit area: an outer
    /// frame around a glass button style adds space, not hit area (the More button measured 42 × 19 pt that way).
    func glassCircle(diameter: CGFloat) -> some View {
        frame(width: diameter, height: diameter)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
    }
}
