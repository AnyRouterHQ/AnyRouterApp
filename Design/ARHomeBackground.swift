import SwiftUI

/// Empty-chat background: the system background with a soft linear wash of the accent color at the
/// top that fades out by 45% of the height. Static, no blob, no mesh. It extends under the status bar.
enum ARHomeWash {
    static let topOpacityLight = 0.12
    static let topOpacityDark = 0.20
    static let fadeEnd = 0.45
}

struct ARHomeBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.accentColor.opacity(scheme == .dark ? ARHomeWash.topOpacityDark : ARHomeWash.topOpacityLight), location: 0),
                .init(color: Color.accentColor.opacity(0), location: ARHomeWash.fadeEnd),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
