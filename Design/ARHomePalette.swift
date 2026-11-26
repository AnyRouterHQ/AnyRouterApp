import SwiftUI
import UIKit

/// Colors and motion for the empty-chat background: a soft mesh of the brand orange blended into warm neutrals.
/// Each theme has its own palette; the lightest mesh colour keeps the secondary text at 4.5:1 or better.
enum ARHomePalette {
    /// 3x3 mesh, row-major. The bottom row equals the plain app background so the mesh fades into the composer area.
    static let lightMesh: [UInt32] = [
        0xFFE9D9, 0xFFF3EA, 0xFFE3CF,
        0xFFF1E6, 0xFFD9BF, 0xFFF6EF,
        0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
    ]
    static let darkMesh: [UInt32] = [
        0x2A1A10, 0x1E1612, 0x3A2111,
        0x24180F, 0x4A2A14, 0x1F1712,
        0x121212, 0x121212, 0x121212,
    ]
    static let lightSecondaryText: UInt32 = 0x595959
    static let darkSecondaryText: UInt32 = 0xC4C4C4

    static func mesh(dark: Bool) -> [UInt32] { dark ? darkMesh : lightMesh }

    /// Subtitle and chip captions on the home screen.
    static let secondaryText = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? darkSecondaryText : lightSecondaryText)
    })

    /// Mesh control points. Only the interior points drift, by a few percent over a slow cycle.
    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ phase: Double, _ amount: Float) -> Float { Float(sin(time * 0.21 + phase)) * amount }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + drift(0, 0.07), 0.45 + drift(1.3, 0.06)], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }
}

/// Slowly moving mesh behind the greeting. Static under Reduce Motion.
struct ARHomeBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            MeshGradient(
                width: 3, height: 3,
                points: ARHomePalette.points(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                colors: ARHomePalette.mesh(dark: scheme == .dark).map { Color(uiColor: UIColor(hex: $0)) }
            )
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5),
                                     .init(color: .clear, location: 0.95)],
                             startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
