import SwiftUI

/// First launch: the logo, one line, then Log in to AnyRouter (system web sheet) or Use local models only.
struct OnboardingScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    var onFinish: () -> Void

    @State private var flow = SignInFlow.State.signedOut
    @State private var showsLocalStep = false

    private var appleAvailable: Bool { models.models.contains { $0.source == .apple && $0.isInstalled } }
    private var signedIn: Bool { app.account.state.isSignedIn }
    private var authorizing: Bool {
        if case .authorizing = flow { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 12) {
                    ARLogoMark(size: 64).foregroundStyle(.primary).accessibilityHidden(true)
                    Text("AnyRouter").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("One chat for models on your device and in the cloud.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
                VStack(spacing: 12) {
                    if case .failed(let reason, _) = flow {
                        Text(reason.text).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Button { signedIn ? finishWithCloud() : authorize(.signIn) } label: {
                        Group {
                            if authorizing {
                                HStack(spacing: 8) { ProgressView(); Text("Opening AnyRouter…") }
                            } else {
                                Text("Log in to AnyRouter")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authorizing)
                    .accessibilityIdentifier("onboarding.signIn")
                    Button("Use local models only") { useOnDevice() }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .disabled(authorizing)
                        .accessibilityIdentifier("onboarding.onDevice")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: Self.readableWidth)
            .frame(maxWidth: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsLocalStep) { OnboardingLocalStep(onFinish: onFinish) }
        }
    }

    // MARK: Actions

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
