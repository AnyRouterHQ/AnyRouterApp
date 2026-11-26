import SwiftUI

struct ThemeSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Section {
                Toggle("Show response details", isOn: $settings.showResponseDetails)
            } footer: {
                Text("The model, cost and speed under each reply.")
            }
        }
    }
}
