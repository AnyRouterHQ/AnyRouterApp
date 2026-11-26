import SwiftUI

/// How replies are shaped and shown: system prompt, max tokens, temperature, top P, and the line under each reply.
struct ResponseCustomizationSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("System prompt") {
                TextField("Optional", text: $settings.systemPrompt, axis: .vertical).lineLimit(3...8)
            }
            Section("Length") {
                HStack {
                    Text("Max tokens")
                    Spacer()
                    TextField("No limit", value: $settings.maxTokens, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
            }
            Section("Sampling") {
                slider("Temperature", value: $settings.temperature, range: 0...2, step: 0.05)
                slider("Top P", value: $settings.topP, range: 0...1, step: 0.01)
            }
            Section {
                Toggle("Show response details", isOn: $settings.showResponseDetails)
                    .accessibilityIdentifier("settings-show-response-details")
                ResponseDetailsPreview(showsDetails: settings.showResponseDetails)
            } header: {
                Text("Replies")
            } footer: {
                Text("The model, cost and speed under each reply.")
            }
            Section {
                Button("Reset to defaults", role: .destructive) { settings.resetGenerationDefaults() }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
