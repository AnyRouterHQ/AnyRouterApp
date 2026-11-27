import SwiftUI

/// How replies are shaped and shown: system prompt, max tokens, temperature, top P, the reply text, and the line under each reply.
struct ResponseCustomizationSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
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
                Toggle("Show response details", isOn: $settings.showResponseDetails)
                    .accessibilityIdentifier("settings-show-response-details")
                ResponseDetailsPreview(showsDetails: settings.showResponseDetails)
            } header: {
                Text("Replies")
            } footer: {
                Text("Cost, speed and tokens open under the model name below each reply.")
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
