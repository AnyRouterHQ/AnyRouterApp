import SwiftUI

/// The icon of a tool source: an SF Symbol, or a bundled template image, in one square so a list of them lines up. It
/// follows the text size.
struct ToolSourceIcon: View {
    let icon: ToolSource.Icon
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name).imageScale(.large)
            case .asset(let name):
                Image(name).resizable().renderingMode(.template).scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}
