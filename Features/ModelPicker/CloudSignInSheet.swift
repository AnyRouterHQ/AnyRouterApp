import SwiftUI

/// Shown when a signed-out person taps a cloud model: why to sign in, and the two ways to do it.
struct CloudSignInSheet: View {
    let model: ModelDescriptor
    let error: String?
    let isWorking: Bool
    let signIn: (AuthMode) -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ARLogoMark(size: 56).foregroundStyle(.primary).accessibilityHidden(true)
            Text("Sign in to use \(model.shortName)")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("AnyRouter is one account for hundreds of cloud models, with automatic failover when one is down.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error { SignInFailureNotice(raw: error) }
            VStack(spacing: 8) {
                Button { signIn(.signIn) } label: { Text("Sign in").prominentLabel().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cloud-signin.sign-in")
                Button { signIn(.signUp) } label: { Text("Create account").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cloud-signin.create-account")
                Button("Not now", action: notNow)
                    .accessibilityIdentifier("cloud-signin.not-now")
            }
            .controlSize(.large)
            .disabled(isWorking)
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
