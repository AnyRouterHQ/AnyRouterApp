import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct OAuthRetryTests {
    private func client(_ api: StubbedAPI) -> OAuthClient { OAuthClient(config: api.config, urlSession: api.session) }

    @Test func registrationRetriesOnceAfterAServerError() async throws {
        let calls = Counter()
        let api = StubbedAPI { _ in
            calls.next() == 1
                ? .init(status: 503, body: Data(#"{"error":{"message":"The database is briefly unavailable."}}"#.utf8))
                : .init(body: Data(#"{"client_id":"abc"}"#.utf8))
        }
        let id = try await client(api).register(redirect: "http://127.0.0.1:1/callback")
        #expect(id == "abc")
        #expect(calls.next() == 3)
    }

    @Test func registrationGivesUpAfterTheSecondServerError() async {
        let calls = Counter()
        let api = StubbedAPI { _ in _ = calls.next(); return .init(status: 503) }
        await #expect(throws: OAuthClient.Failure.self) {
            _ = try await client(api).register(redirect: "http://127.0.0.1:1/callback")
        }
        #expect(calls.next() == 3)
    }

    @Test func tokenExchangeIsNeverRetriedAndReportsBusy() async {
        let calls = Counter()
        let api = StubbedAPI { _ in _ = calls.next(); return .init(status: 503) }
        do {
            _ = try await client(api).exchange(code: "c", verifier: "v", clientID: "id", redirect: "http://127.0.0.1:1/callback")
            Issue.record("expected a failure")
        } catch {
            #expect(error.localizedDescription == "AnyRouter is busy. Try again.")
        }
        #expect(calls.next() == 2)
    }

    @Test func clientErrorsKeepTheirServerMessageAndAreNotRetried() async {
        let calls = Counter()
        let api = StubbedAPI { _ in
            _ = calls.next()
            return .init(status: 400, body: Data(#"{"error_description":"bad code"}"#.utf8))
        }
        do {
            _ = try await client(api).register(redirect: "x")
            Issue.record("expected a failure")
        } catch {
            #expect(error.localizedDescription == "bad code")
        }
        #expect(calls.next() == 2)
    }

    @Test func retryDelayFollowsRetryAfterCappedAtThreeSeconds() {
        #expect(OAuthClient.retryDelay("2") == 2)
        #expect(OAuthClient.retryDelay("120") == 3)
        #expect(OAuthClient.retryDelay(nil) == 1)
        #expect(OAuthClient.retryDelay("soon") == 1)
        #expect(OAuthClient.retryDelay("-4") == 1)
    }
}
