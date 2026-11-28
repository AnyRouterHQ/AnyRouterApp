import SwiftUI

/// First launch. Say what the app can chat with, then offer the two ways in: AnyRouter (sign in or create an
/// account in the system web sheet) or on-device only. Standard Form rows and system buttons only.
struct OnboardingScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    var onFinish: () -> Void

    @State private var flow = SignInFlow.State.signedOut
    @State private var showsLocalStep = false
    /// The screen's width, so the list keeps the buttons' readable width on iPad.
    @State private var width: CGFloat = 0

    private var appleAvailable: Bool { models.models.contains { $0.source == .apple && $0.isInstalled } }
    private var signedIn: Bool { app.account.state.isSignedIn }
    private var authorizing: Bool {
        if case .authorizing = flow { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        ARLogoMark(size: 52).foregroundStyle(.primary).accessibilityHidden(true)
                        Text("Welcome to AnyRouter").font(.largeTitle.bold()).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("One chat for models on your device and in the cloud.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }
                Section("Chat with") {
                    source("Apple Intelligence", detail: "Private and on device. No download.", icon: "apple.logo")
                    source("Local models", detail: "Download open models and run them on this device.", icon: "iphone")
                    source("AnyRouter cloud", detail: "Hundreds of cloud models with one account.", icon: "cloud")
                }
                if case .failed(let reason, let mode) = flow {
                    Section {
                        Label(reason.text, systemImage: "exclamationmark.triangle")
                        Button("Try again") { authorize(mode) }
                    }
                }
            }
            .formStyle(.grouped)
            .readableWidth(Self.readableWidth, in: width)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .navigationBarTitleDisplayMode(.inline)
            // The actions stay reachable at the bottom, above the home indicator. A bar, not a painted band: the scroll
            // edge effect gives it depth.
            .safeAreaBar(edge: .bottom) { actions }
            .navigationDestination(isPresented: $showsLocalStep) { OnboardingLocalStep(onFinish: onFinish) }
        }
    }

    private func source(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                // Two lines reserved on every row, so the three rows share one height: a two-line row between one-line
                // rows left a 1 px black seam under its separator in dark mode (screenshots 46091121132).
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            // Every separator starts under the text, as in a stock list; left to the default, the one under
            // "Local models" ran to the edge (screenshots 46075429647).
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        } icon: {
            Image(systemName: icon).imageScale(.large)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button { signedIn ? finishWithCloud() : authorize(.signIn) } label: {
                Group {
                    if authorizing {
                        HStack(spacing: 8) { ProgressView(); Text("Opening AnyRouter…") }
                    } else {
                        Text(signedIn ? "Continue" : "Continue with AnyRouter")
                    }
                }
                .prominentLabel()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(authorizing)
            .accessibilityIdentifier("onboarding.signIn")
            if !signedIn {
                // Glass, not bordered: the bordered fill nearly vanished on the light and dark backgrounds.
                Button { authorize(.signUp) } label: { Text("Create account").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(authorizing)
                    .accessibilityIdentifier("onboarding.signUp")
            }
            Button("Use on-device only") { useOnDevice() }
                .controlSize(.large)
                .disabled(authorizing)
                .accessibilityIdentifier("onboarding.onDevice")
        }
        // A readable width on iPad instead of buttons across the whole screen.
        .frame(maxWidth: Self.readableWidth)
        .padding()
        .frame(maxWidth: .infinity)
    }

    private static let readableWidth: CGFloat = 560

    /// Opens the web sheet. A new account comes back signed in: the sheet ends at the same consent step as
    /// sign-in, so there is no second login. The email can be verified later (see Settings).
    private func authorize(_ mode: AuthMode) {
        guard !authorizing else { return }
        flow = SignInFlow.reduce(flow, .start(mode))
        guard authorizing else { return }
        Task {
            do {
                try await app.account.signIn(mode: mode)
            } catch let error as AnyRouterAccountAdapter.SignInFailed where error.isBusy {
                flow = SignInFlow.reduce(flow, .failed(.busy))
                return
            } catch {
                flow = SignInFlow.reduce(flow, .failed(.message(error.localizedDescription)))
                return
            }
            guard app.account.state.isSignedIn else {
                flow = SignInFlow.reduce(flow, .cancelled)
                return
            }
            await app.account.refreshSummary()
            flow = SignInFlow.reduce(flow, .succeeded(emailVerified: app.account.summary?.emailVerified))
            await finish(.cloud)
        }
    }

    private func useOnDevice() {
        switch OnboardingLogic.onDeviceRoute(appleAvailable: appleAvailable) {
        case .chat(let choice): Task { await finish(choice) }
        case .pickLocal: showsLocalStep = true
        }
    }

    private func finishWithCloud() { Task { await finish(.cloud) } }

    private func finish(_ choice: OnboardingLogic.Choice) async {
        await models.refresh()
        if let id = OnboardingLogic.modelID(for: choice, models: models.models, local: nil) {
            models.select(modelID: id)
        }
        onFinish()
    }
}

#Preview("Onboarding") {
    let state = AppState()
    return OnboardingScreen {}
        .environment(state)
        .environment(state.models)
}

private extension View {
    /// On a screen much wider than `maxWidth` the list's rows keep that width, centred, like the buttons under them.
    @ViewBuilder
    func readableWidth(_ maxWidth: CGFloat, in width: CGFloat) -> some View {
        if width > maxWidth + 80 {
            contentMargins(.horizontal, (width - maxWidth) / 2, for: .scrollContent)
        } else {
            self
        }
    }
}
