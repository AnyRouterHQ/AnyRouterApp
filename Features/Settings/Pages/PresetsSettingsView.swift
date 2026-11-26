import SwiftUI

/// Presets page inside Settings. The presets lane owns `PresetsSettingsSheet`.
struct PresetsSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        PresetsSettingsSheet(store: app.presets)
    }
}
