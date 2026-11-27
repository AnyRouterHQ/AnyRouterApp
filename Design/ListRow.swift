import SwiftUI

/// The one list row of the app, as in iOS Settings: an icon slot, a title, up to two lines of secondary text and
/// trailing accessories. The container adds the rest: a NavigationLink its chevron, a Toggle its switch, a Link or a
/// Button the tap. Plain content only: no glass and no card chrome on list rows.
struct ListRow<Icon: View, Accessory: View>: View {
    let title: String
    let secondary: Text?
    let icon: Icon
    let accessory: Accessory

    init(
        _ title: String, subtitle: String? = nil,
        @ViewBuilder icon: () -> Icon, @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title, secondary: subtitle.flatMap { $0.isEmpty ? nil : Text($0) }, icon: icon, accessory: accessory)
    }

    /// Secondary text with its own styling, such as a fit status in green or red inside the gray line.
    init(
        _ title: String, secondary: Text?,
        @ViewBuilder icon: () -> Icon, @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.secondary = secondary
        self.icon = icon()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let secondary {
                        secondary.font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                // Separators start under the title, not under the icon, as in iOS Settings.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            } icon: {
                icon
            }
            Spacer(minLength: 0)
            accessory
        }
        .frame(minHeight: 44)
    }
}

extension ListRow where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder icon: () -> Icon) {
        self.init(title, subtitle: subtitle, icon: icon) { EmptyView() }
    }

    init(_ title: String, secondary: Text?, @ViewBuilder icon: () -> Icon) {
        self.init(title, secondary: secondary, icon: icon) { EmptyView() }
    }
}

/// The accessory of a row that leaves the app: the system's outbound arrow, as in iOS Settings.
struct OutboundArrow: View {
    var body: some View {
        Image(systemName: "arrow.up.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

#Preview {
    List {
        ListRow("Local Models", subtitle: "2 installed · 1.3 GB") {
            SettingsIcon(glyph: .symbol("cube"), color: .green)
        }
        ListRow("Read the full text", icon: { Image(systemName: "hand.raised") }) { OutboundArrow() }
    }
}
