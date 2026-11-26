import XCTest

@testable import AnyRouter

final class PKCETests: XCTestCase {
    /// RFC 7636 appendix B.
    func testS256ChallengeMatchesRFCVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierIsBase64URLWithValidLength() throws {
        let verifier = try PKCE.makeVerifier()
        XCTAssertEqual(verifier.count, 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertNotEqual(verifier, try PKCE.makeVerifier())
    }

    func testLoopbackOnlyAcceptsCodeWithExpectedState() {
        let good = URL(string: "http://127.0.0.1:5000/callback?code=abc&state=s1")!
        let wrongState = URL(string: "http://127.0.0.1:5000/callback?code=abc&state=other")!
        let noCode = URL(string: "http://127.0.0.1:5000/callback?state=s1")!
        XCTAssertTrue(LoopbackCallback.hasCodeAndState(good, state: "s1"))
        XCTAssertFalse(LoopbackCallback.hasCodeAndState(wrongState, state: "s1"))
        XCTAssertFalse(LoopbackCallback.hasCodeAndState(noCode, state: "s1"))
    }

    func testCallbackTargetMustBeCallbackPath() {
        XCTAssertNotNil(LoopbackCallback.callbackURL("/callback?code=a&state=b", port: 5000))
        XCTAssertNil(LoopbackCallback.callbackURL("/other?code=a&state=b", port: 5000))
        XCTAssertNil(LoopbackCallback.callbackURL("http://evil.example:5000/callback?code=a", port: 5000))
        XCTAssertNil(LoopbackCallback.callbackURL("/callback", port: 0))
    }
}
