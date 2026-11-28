import Testing

@testable import AnyRouter

struct SignInFailureTextTests {
    @Test func aServerRefusalBecomesOneGenericLine() {
        #expect(SignInFailureText.plain(for: "invalid_request: redirect_uri is not registered") == SignInFailureText.generic)
        #expect(SignInFailureText.plain(for: "Registration failed (HTTP 400)") == SignInFailureText.generic)
    }

    @Test func aDeclinedSignInSaysSo() {
        #expect(SignInFailureText.plain(for: "access_denied: The user denied access") == SignInFailureText.declined)
    }

    @Test func noNetworkSaysToCheckTheConnection() {
        #expect(SignInFailureText.plain(for: "The Internet connection appears to be offline.") == SignInFailureText.offline)
        #expect(SignInFailureText.plain(for: "The request timed out.") == SignInFailureText.offline)
    }

    @Test func theBusyLineStaysAsIs() {
        #expect(SignInFailureText.plain(for: SignInFailureText.busy) == SignInFailureText.busy)
    }
}
