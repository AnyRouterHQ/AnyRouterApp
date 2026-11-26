import SwiftUI

/// Titled card of related rows (used by the pages pushed from Settings).
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            ARSectionTitle(title)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .arCard(radius: ARTheme.radiusLarge)
        }
    }
}

struct SettingsText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.arSM).foregroundStyle(ARColor.mutedForeground).frame(maxWidth: .infinity, alignment: .leading)
    }
}
