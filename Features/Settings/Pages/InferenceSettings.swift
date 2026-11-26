import SwiftUI

/// Generation defaults: system prompt, max tokens, temperature, top P.
struct InferenceSettings: View {
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
