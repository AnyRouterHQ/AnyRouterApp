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
        Button("Sign in with AnyRouter") { signIn(.signIn) }
        Button("Create account") { signIn(.signUp) }
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
                Text(summary?.title ?? "AnyRouter account").font(.headline).lineLimit(1)
                if let email = summary?.email, email != summary?.title {
                    Text(email).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let plan = summary?.plan {
                    Text("\(plan) plan").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        if summary?.needsEmailVerification == true {
            VStack(alignment: .leading, spacing: 4) {
                Label("Verify your email", systemImage: "envelope.badge")
                Text("Chat works as usual. Some free credits wait until your email is verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Link("Open anyrouter.dev", destination: Self.emailSettingsURL)
        }
        if let line = summary?.usageLine { Text(line) }
        Link("Manage on anyrouter.dev", destination: Self.manageURL)
        Button("Sign out", role: .destructive) {
            Task { await app.account.signOut(); await models.refresh() }
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

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(initials).font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
