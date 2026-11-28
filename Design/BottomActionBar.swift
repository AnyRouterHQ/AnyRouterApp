import SwiftUI

extension View {
    /// The screen's one primary action at the bottom: a large prominent glass button in the safe-area bar, so the list
    /// scrolls under it with the system's edge effect instead of a painted band. `accessory` sits above the button (a
    /// reason it is disabled, secondary actions).
    func bottomActionBar<ButtonLabel: View, Accessory: View>(
        id: String, isEnabled: Bool, action: @escaping () -> Void,
        @ViewBuilder label: () -> ButtonLabel, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let label = label()
        let accessory = accessory()
        return safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                accessory
                // A disabled prominent button with the mono tint drew white on white in light mode (screenshots
                // 46140428971), so a disabled action is plain glass with dimmed text, still clearly a button.
                if isEnabled {
                    Button(action: action) { label.frame(maxWidth: .infinity).prominentLabel() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier(id)
                } else {
                    Button(action: action) { label.frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(true)
                        .accessibilityIdentifier(id)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}
