import SwiftUI

/// How replies look and read: the reply text, custom instructions and the line under each reply. Length and sampling are under Advanced.
struct ResponseCustomizationSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                VStack(spacing: 4) {
                    HStack {
                        Text("Text size")
                        Spacer()
                        Text(ReplyText.label(step: settings.replyTextStep)).foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.replyTextStep) },
                            set: { settings.replyTextStep = Int($0.rounded()) }),
                        in: Double(ReplyText.steps.lowerBound)...Double(ReplyText.steps.upperBound), step: 1
                    ) {
                        Text("Text size")
                    } minimumValueLabel: {
                        Text("A").font(.footnote)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    .accessibilityValue(ReplyText.label(step: settings.replyTextStep))
                    .accessibilityIdentifier("settings-reply-text-size")
                }
                Picker("Font", selection: $settings.replyFont) {
                    ForEach(ReplyFont.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings-reply-font")
                ReplyTextPreview()
            } header: {
                Text("Reply text")
            } footer: {
                Text("Adds to your system text size. Code stays monospaced.")
            }
            Section {
                NavigationLink {
                    CustomInstructionsScreen()
                } label: {
                    LabeledContent("Custom instructions", value: InstructionsLogic.summary(global: settings.systemPrompt))
                }
                .accessibilityIdentifier("settings-custom-instructions")
            } footer: {
                Text("Told to every model at the start of a chat. Change them for one chat from its menu.")
            }
            Section {
                Toggle("Show response details", isOn: $settings.showResponseDetails)
                    .accessibilityIdentifier("settings-show-response-details")
                ResponseDetailsPreview(showsDetails: settings.showResponseDetails)
            } header: {
                Text("Replies")
            } footer: {
                Text("Cost, speed and tokens open under the model name below each reply.")
            }
            Section {
                NavigationLink("Advanced") { ResponseAdvancedSettings() }
                    .accessibilityIdentifier("settings-response-advanced")
            } footer: {
                Text("Length and sampling.")
            }
        }
        .formSwitches()
    }
}

/// Length and sampling, kept off the main page: most people never change them.
struct ResponseAdvancedSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Length") {
                HStack {
                    Text("Max tokens")
                    Spacer()
                    // Zero means no limit; an empty field reads "Automatic" instead of a bare 0.
                    TextField(
                        "Automatic",
                        value: Binding(
                            get: { settings.maxTokens == 0 ? nil : settings.maxTokens },
                            set: { settings.maxTokens = $0 ?? 0 }),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .accessibilityIdentifier("settings-max-tokens")
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
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
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
