import Foundation

/// Which page the browser sign-in opens first. Both end in the same authorize flow, so a new
/// account comes back to the app already signed in.
enum AuthMode: Equatable, Sendable {
    case signIn
    case signUp
}
