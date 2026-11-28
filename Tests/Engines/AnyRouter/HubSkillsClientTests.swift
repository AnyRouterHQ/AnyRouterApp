import Foundation
import Testing
@testable import AnyRouter

struct HubSkillsClientTests {
    private let bundle = """
        {"base_url":"https://anyrouter.dev/api","generated_at":"2026-11-28T00:00:00Z","hubs":[
         {"slug":"mine","name":"Mine","visibility":"private","items":[
           {"slug":"bill-splitter","kind":"skill","description":"Split a bill.","body":"1. Ask.","version":3,"content_hash":"abc","security_scan_status":"ok","files":{}},
           {"slug":"styled","kind":"skill","body":"---\\nname: styled\\ndescription: Styled.\\n---\\nSteps.","security_scan_status":"warn"},
           {"slug":"bad","kind":"skill","description":"Flagged.","body":"x","security_scan_status":"flagged"},
           {"slug":"notes","kind":"kb","description":"Not a skill.","body":"x"},
           {"slug":"no-body","kind":"skill","description":"No body."},
           {"kind":"skill","description":"No slug.","body":"x"}]},
         {"name":"No slug","items":[{"slug":"lost","kind":"skill","body":"x"}]},
         {"slug":"empty"}]}
        """

    private func client(_ api: StubbedAPI) -> HubSkillsClient { HubSkillsClient(config: api.config, session: api.session) }

    @Test func parseKeepsUnflaggedSkillsAndIgnoresTheRest() throws {
        let items = try HubSkillsClient.parse(Data(bundle.utf8))
        #expect(items.map(\.ref) == ["mine/bill-splitter", "mine/styled"])
        #expect(items[0] == HubSkillItem(hub: "mine", slug: "bill-splitter", description: "Split a bill.", body: "1. Ask."))
        #expect(items[1].description == nil && items[1].body.hasPrefix("---"))
    }

    @Test func aBodyWithoutAHubsListIsAFailureNotAnEmptyAnswer() throws {
        #expect(try HubSkillsClient.parse(Data(#"{"hubs":[]}"#.utf8)).isEmpty)
        for body in ["", "not json", "[]", #"{"items":[]}"#, #"{"hubs":"none"}"#] {
            #expect(throws: AnyRouterError.badResponse) { try HubSkillsClient.parse(Data(body.utf8)) }
        }
    }

    @Test func syncSendsTheKeyAndTheAppHeadersToHubsSync() async throws {
        let body = bundle
        let api = StubbedAPI { request in
            let ok = request.url?.path == "/api/v1/hubs/sync" && request.httpMethod == "GET"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer key-1"
                && request.value(forHTTPHeaderField: "X-AnyRouter-Source") == "ios-app"
            return ok ? StubRegistry.Reply(body: Data(body.utf8)) : StubRegistry.Reply(status: 400)
        }
        let items = try await client(api).sync(tokens: FakeTokens("key-1"))
        #expect(items.count == 2)
    }

    @Test func aRefusedSignInIsAMessageAndNeverSignsTheUserOut() async throws {
        for status in [401, 403] {
            let api = StubbedAPI { _ in StubRegistry.Reply(status: status, body: Data(#"{"error":{"message":"nope"}}"#.utf8)) }
            let tokens = FakeTokens("key-1")
            await #expect(throws: AnyRouterError.http(status: status, message: HubSkillsClient.refusedText)) {
                try await client(api).sync(tokens: tokens)
            }
            #expect(tokens.clearCount == 0 && tokens.token() == "key-1")
        }
    }

    @Test func aServerErrorKeepsItsOwnMessage() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 500, body: Data(#"{"error":{"message":"Hub store is down"}}"#.utf8)) }
        await #expect(throws: AnyRouterError.http(status: 500, message: "Hub store is down")) {
            try await client(api).sync(tokens: FakeTokens("key-1"))
        }
    }

    @Test func noKeyMeansSignedOutAndNoRequest() async {
        let api = StubbedAPI { _ in Issue.record("no request without a key"); return StubRegistry.Reply(status: 500) }
        await #expect(throws: AnyRouterError.signedOut) { try await client(api).sync(tokens: FakeTokens(nil)) }
    }

    @Test func anUnreadableAnswerIsABadResponse() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(body: Data("<html>".utf8)) }
        await #expect(throws: AnyRouterError.badResponse) { try await client(api).sync(tokens: FakeTokens("key-1")) }
    }

    @Test func theDefaultClientTalksToAnyRouter() {
        let standard = HubSkillsClient()
        #expect(standard.config.baseURL == AnyRouterConfig.standard.baseURL)
    }
}
