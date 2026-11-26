import SwiftUI

/// Brand mark (template image, tinted by the foreground style).
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

/// Round icon button used in the floating top bar (menu, new chat, back).
struct ARIconButton: View {
    let systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ARColor.foreground)
                .frame(width: ARTheme.controlSize, height: ARTheme.controlSize)
                .background(ARColor.card, in: Circle())
                .overlay(Circle().strokeBorder(ARColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Small tag pill (model tags such as "fast", "vision").
struct ARChip: View {
    let text: String
    var tint: Color = ARColor.mutedForeground

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Full-width action button. `.filled` is the light/dark inverted primary, `.destructive` the red text variant.
struct ARButtonStyle: ButtonStyle {
    enum Kind { case filled, secondary, destructive }
    var kind: Kind = .filled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(background, in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .filled: ARColor.primaryForeground
        case .secondary: ARColor.foreground
        case .destructive: ARColor.destructive
        }
    }

    private var background: Color {
        switch kind {
        case .filled: ARColor.primary
        case .secondary, .destructive: ARColor.secondary
        }
    }
}

extension ButtonStyle where Self == ARButtonStyle {
    static var arFilled: ARButtonStyle { ARButtonStyle(kind: .filled) }
    static var arSecondary: ARButtonStyle { ARButtonStyle(kind: .secondary) }
    static var arDestructive: ARButtonStyle { ARButtonStyle(kind: .destructive) }
}

/// Rounded search field (sidebar and hub search).
struct ARSearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ARColor.mutedForeground)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(ARColor.mutedForeground))
                .font(.arBase)
                .foregroundStyle(ARColor.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(ARColor.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous).strokeBorder(ARColor.border, lineWidth: 1))
    }
}

/// Muted section caption ("Installed Models", "Pinned").
struct ARSectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ARColor.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Top bar for full-screen pages (hub, settings): back circle plus title.
struct ARPageHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ARIconButton(systemName: "arrow.left", label: "Back", action: onBack)
            Text(title)
                .font(.arXL)
                .foregroundStyle(ARColor.foreground)
            Spacer()
        }
        .padding(.horizontal, ARTheme.pagePadding)
        .padding(.vertical, 8)
    }
}

/// Placeholder for surfaces that stay visible but are not wired yet.
struct ARComingSoon: View {
    let title: String
    var systemImage: String = "sparkles"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon."))
            .foregroundStyle(ARColor.mutedForeground)
    }
}

#Preview("Components") {
    VStack(spacing: 16) {
        HStack { ARIconButton(systemName: "line.3.horizontal", label: "Menu") {}; ARLogoMark(); ARChip(text: "fast") }
        ARSearchField(text: .constant(""), prompt: "Search chats")
        Button("Download") {}.buttonStyle(.arFilled)
        Button("Delete") {}.buttonStyle(.arDestructive)
    }
    .padding()
    .background(ARColor.background)
}
