import SwiftUI

/// Settings: account, providers, catalog sources, generation defaults, appearance, about.
struct SettingsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(ModelStore.self) private var models
    @Environment(ShellModel.self) private var shell

    @State private var signInError: String?
    @State private var showsCatalog = false
    @State private var showsLicenses = false

    private var appleAvailable: Bool { models.models.contains { $0.source == .apple && $0.isInstalled } }
    private var localInstalled: Int { models.models.filter { ($0.source == .gguf || $0.source == .mlx) && $0.isInstalled }.count }
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            ARPageHeader(title: "Settings") { shell.open(.chat, closeSidebar: false) }
            ScrollView {
                VStack(spacing: 20) {
                    accountSection
                    providersSection
                    catalogSection
                    generationSection(settings: $settings)
                    appearanceSection(settings: $settings)
                    aboutSection
                }
                .frame(maxWidth: ARTheme.contentMaxWidth)
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showsCatalog) { CatalogSourcesSheet() }
        .sheet(isPresented: $showsLicenses) { LicensesSheet() }
    }

    // MARK: Sections

    private var accountSection: some View {
        SettingsGroup("Account") {
            switch app.account.state {
            case .signedOut:
                SettingsText("Sign in to use AnyRouter cloud models.")
                Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.arFilled)
                if let signInError { Text(signInError).font(.arXS).foregroundStyle(ARColor.destructive) }
            case .signingIn:
                HStack { ProgressView(); Text("Signing in…").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
            case .signedIn(let label):
                SettingsRow("Signed in", value: label ?? "AnyRouter", systemImage: "person.crop.circle.badge.checkmark")
                Button("Sign out") {
                    Task { await app.account.signOut(); await models.refresh() }
                }.buttonStyle(.arDestructive)
            }
        }
    }

    private var providersSection: some View {
        SettingsGroup("Model providers") {
            SettingsRow("Apple Intelligence", value: appleAvailable ? "Available" : "Unavailable", systemImage: "apple.logo")
            SettingsRow("AnyRouter", value: app.account.state.isSignedIn ? "Signed in" : "Signed out", systemImage: "cloud")
            SettingsRow("On-device models", value: "\(localInstalled) installed", systemImage: "iphone")
            Button("Browse models") { shell.open(.hub, closeSidebar: false) }.buttonStyle(.arSecondary)
        }
    }

    private var catalogSection: some View {
        SettingsGroup("Model catalog") {
            SettingsText("Add Hugging Face repos or a remote catalog to the Browse Models list.")
            Button("Catalog sources") { showsCatalog = true }.buttonStyle(.arSecondary)
        }
    }

    private func generationSection(settings: Bindable<AppSettings>) -> some View {
        SettingsGroup("Generation defaults") {
            labeledSlider("Temperature", value: settings.temperature, range: 0...2, step: 0.05)
            labeledSlider("Top P", value: settings.topP, range: 0...1, step: 0.01)
            HStack {
                Text("Max tokens").font(.arBase).foregroundStyle(ARColor.foreground)
                Spacer()
                TextField("No limit", value: settings.maxTokens, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .foregroundStyle(ARColor.foreground)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("System prompt").font(.arBase).foregroundStyle(ARColor.foreground)
                TextField("Optional", text: settings.systemPrompt, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            }
            Button("Reset to defaults") { settings.wrappedValue.resetGenerationDefaults() }.buttonStyle(.arSecondary)
        }
    }

    private func appearanceSection(settings: Bindable<AppSettings>) -> some View {
        SettingsGroup("Appearance") {
            Picker("Appearance", selection: settings.appearance) {
                ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        SettingsGroup("About") {
            SettingsRow("AnyRouter", value: "Version \(version)", systemImage: "info.circle")
            SettingsText("Open source under the Apache License 2.0.")
            if let url = URL(string: "https://github.com/AnyRouterHQ/AnyRouterApp") {
                Link(destination: url) {
                    SettingsRow("Source code", value: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            Button("Licenses") { showsLicenses = true }.buttonStyle(.arSecondary)
        }
    }

    // MARK: Helpers

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.arBase).foregroundStyle(ARColor.foreground)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.arSM).foregroundStyle(ARColor.mutedForeground)
            }
            Slider(value: value, in: range, step: step).tint(ARColor.accent)
        }
    }

    private func signIn() {
        signInError = nil
        Task {
            do {
                try await app.account.signIn()
                await models.refresh()
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}

/// Titled card of related rows.
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

struct SettingsRow: View {
    let title: String
    let value: String
    let systemImage: String

    init(_ title: String, value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).frame(width: 22).foregroundStyle(ARColor.mutedForeground)
            Text(title).font(.arBase).foregroundStyle(ARColor.foreground)
            Spacer()
            Text(value).font(.arSM).foregroundStyle(ARColor.mutedForeground)
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
