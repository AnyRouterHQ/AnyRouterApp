import SwiftUI

/// Account rows at the top of Settings: signed-in profile and spend, or the sign-in prompt.
/// Standard list rows; the caller puts them in a `Section`.
struct AccountCard: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @Environment(\.scenePhase) private var scenePhase
    @State private var signInError: String?

    private static let manageURL = URL(string: "https://anyrouter.dev/dashboard")!
    /// Where the verification link is sent and resent from. The API has no resend call.
    private static let emailSettingsURL = URL(string: "https://anyrouter.dev/dashboard/settings")!

    var body: some View {
        Group {
            switch app.account.state {
            case .signedOut: signedOut
            case .signingIn:
                HStack(spacing: 12) { ProgressView(); Text("Signing in…").foregroundStyle(.secondary) }
            case .signedIn: signedIn
            }
        }
        .task(id: app.account.state) { await app.account.refreshSummary() }
        // Coming back from the browser after verifying: clear the note without a restart.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.account.refreshSummary() } }
        }
    }

    @ViewBuilder
    private var signedOut: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("AnyRouter").font(.headline)
                Text("Sign in to use cloud models.").font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            ARLogoMark(size: 32).foregroundStyle(.primary)
        }
        // Buttons that look like buttons: with a mono tint, plain list buttons read as static text.
        Button { signIn(.signIn) } label: {
            Text("Sign in with AnyRouter").frame(maxWidth: .infinity).prominentLabel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        Button { signIn(.signUp) } label: {
            Text("Create account").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        if let signInError {
            // Plain, neutral text: server details are not shown to the user.
            Text(signInError).font(.footnote).foregroundStyle(.secondary)
            Button("Try again") { signIn(.signIn) }
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        let summary = app.account.summary
        HStack(spacing: 12) {
            Avatar(url: summary?.avatarURL, initials: summary?.initials ?? "A")
            VStack(alignment: .leading, spacing: 2) {
                // No line limit: at large text sizes two lines still cut the name and the email (accessibility audit, Settings).
                Text(summary?.title ?? "AnyRouter account").font(.headline)
                if let subtitle = summary?.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Menu {
                Link(destination: Self.manageURL) {
                    Label("AnyRouter Dashboard", systemImage: "arrow.up.forward.app")
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await app.account.signOut(); await models.refresh() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Account options")
            .accessibilityIdentifier("account-menu")
        }
        if summary?.needsEmailVerification == true {
            VStack(alignment: .leading, spacing: 4) {
                Label("Verify your email", systemImage: "envelope.badge")
                Text("Chat works as usual. Some free credits wait until your email is verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Link(destination: Self.emailSettingsURL) {
                ListRow("Verify on anyrouter.dev", icon: { Image(systemName: "envelope") }) { OutboundArrow() }
            }
            .foregroundStyle(.primary)
            .accessibilityHint("Opens in Safari")
        }
    }

    private func signIn(_ mode: AuthMode) {
        signInError = nil
        Task {
            do {
                try await app.account.signIn(mode: mode)
                signInError = nil
                await models.refresh()
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}

private struct Avatar: View {
    let url: URL?
    let initials: String
    /// Grows with the name beside it (the audit flagged a fixed 48 pt as Dynamic Type unsupported).
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                // The accent is white in dark mode, so the initials take the background color to stay readable on it.
                Text(initials).font(.headline).foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ARPalette.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
