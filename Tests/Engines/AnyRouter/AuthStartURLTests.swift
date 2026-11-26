import Foundation
import Testing
@testable import AnyRouter

struct AuthStartURLTests {
    private let origin = URL(string: "https://anyrouter.dev")!
    private let authorize = URL(string: "https://anyrouter.dev/api/v1/mcp/oauth/authorize?client_id=c1&redirect_uri=http://127.0.0.1:5000/callback&response_type=code&code_challenge=abc-_&state=s+1")!

    @Test func signInOpensTheAuthorizeURLAsIs() {
        #expect(OAuthClient.startURL(mode: .signIn, authorize: authorize, origin: origin) == authorize)
    }

    @Test func createAccountOpensSignUpWithAuthorizeAsItsReturnPage() throws {
        let start = OAuthClient.startURL(mode: .signUp, authorize: authorize, origin: origin)
        let components = try #require(URLComponents(url: start, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "anyrouter.dev")
        #expect(components.path == "/sign-up")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "redirect_url")
        #expect(components.queryItems?.first?.value == authorize.absoluteString)
    }

    @Test func theNestedURLIsFullyEscapedSoItsOwnParametersSurvive() {
        let start = OAuthClient.startURL(mode: .signUp, authorize: authorize, origin: origin).absoluteString
        let query = start.components(separatedBy: "?").dropFirst().joined(separator: "?")
        #expect(!query.dropFirst("redirect_url=".count).contains("&"), "an unescaped & would split the nested URL")
        #expect(!query.dropFirst("redirect_url=".count).contains("="))
        #expect(query.contains("client_id%3Dc1"))
    }

    @Test func theReturnPageStaysOnTheAnyRouterOriginSoTheServerAcceptsIt() {
        let start = OAuthClient.startURL(mode: .signUp, authorize: authorize, origin: origin)
        let nested = URLComponents(url: start, resolvingAgainstBaseURL: false)?.queryItems?.first?.value.flatMap(URL.init(string:))
        #expect(nested?.host == origin.host)
        #expect(nested?.path == "/api/v1/mcp/oauth/authorize")
    }
}
