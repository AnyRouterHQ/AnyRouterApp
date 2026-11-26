import Foundation
import Testing
@testable import AnyRouter

struct AccountSummaryTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesProfileAndCredits() {
        let me = data(#"{"data":{"name":"Ada Lovelace","email":"ada@example.com","avatar_url":"https://example.com/a.png","plan":"pro"}}"#)
        let credits = data(#"{"balance":12.5,"used":3.25,"free_requests":{"remaining":4,"limit":5}}"#)
        let summary = AccountSummary.parse(me: me, credits: credits, key: nil)
        #expect(summary.displayName == "Ada Lovelace")
        #expect(summary.email == "ada@example.com")
        #expect(summary.avatarURL?.absoluteString == "https://example.com/a.png")
        #expect(summary.plan == "Pro")
        #expect(summary.credits == AccountSummary.Credits(balance: 12.5, used: 3.25))
        #expect(summary.freeRequests == AccountSummary.FreeRequests(remaining: 4, limit: 5))
        #expect(summary.initials == "AL")
        #expect(summary.usageLine == "Credits: \(AccountSummary.money(12.5))")
    }

    /// Shape of the live `GET /api/v1/me` for a sign-in key, whose `/credits` call is rejected.
    @Test func readsAvatarAndBalanceFromLiveMeShape() {
        let me = data(#"{"id":"user_1","email":"ada@example.com","name":"ada","image_url":"https://img.example.com/abc","username":"ada","plan":"go","balance":22.2416}"#)
        let summary = AccountSummary.parse(me: me, credits: nil, key: nil)
        #expect(summary.avatarURL?.absoluteString == "https://img.example.com/abc")
        #expect(summary.credits == AccountSummary.Credits(balance: 22.2416, used: nil))
        #expect(summary.usageLine == "Credits: \(AccountSummary.money(22.2416))")
    }

    @Test func fallsBackToKeyUsageWhenCreditsAreMissing() {
        let key = data(#"{"data":{"label":"sign-in","limit":10,"limit_remaining":7.5,"usage":2.5}}"#)
        let summary = AccountSummary.parse(me: nil, credits: nil, key: key)
        #expect(summary.credits == nil)
        #expect(summary.keyUsage?.label == "sign-in")
        #expect(summary.usageLine == "Key: \(AccountSummary.money(7.5)) of \(AccountSummary.money(10)) left")
    }

    @Test func keyWithoutLimitShowsUsageOnly() {
        let summary = AccountSummary.parse(me: nil, credits: nil, key: data(#"{"data":{"usage":1.5,"limit":null}}"#))
        #expect(summary.usageLine == "Key usage: \(AccountSummary.money(1.5))")
    }

    @Test func missingFieldsAndGarbageDoNotCrash() {
        let summary = AccountSummary.parse(me: data("not json"), credits: data("{}"), key: data("[]"))
        #expect(summary.isEmpty)
        #expect(summary.title == "AnyRouter account")
        #expect(summary.initials == "A")
        #expect(summary.usageLine == nil)
    }

    @Test func insecureAvatarAndBlankNamesAreDropped() {
        let me = data(#"{"name":"  ","email":"grace.hopper@example.com","image":"http://example.com/a.png"}"#)
        let summary = AccountSummary.parse(me: me, credits: nil, key: nil)
        #expect(summary.displayName == nil)
        #expect(summary.avatarURL == nil)
        #expect(summary.title == "grace.hopper@example.com")
        #expect(summary.initials == "GH")
    }

    @Test func planAsObjectAndBooleanNumbersAreHandled() {
        let me = data(#"{"plan":{"name":"go"}}"#)
        let credits = data(#"{"balance":true}"#)
        let summary = AccountSummary.parse(me: me, credits: credits, key: nil)
        #expect(summary.plan == "Go")
        #expect(summary.credits == nil)
    }
}

struct AccountSummaryLoaderTests {
    private func loader(_ responses: [String: (String, Int)], calls: CallLog) -> AccountSummaryLoader {
        AccountSummaryLoader(baseURL: URL(string: "https://example.test/api/v1")!) { request in
            let path = request.url?.lastPathComponent ?? ""
            calls.add(path, auth: request.value(forHTTPHeaderField: "Authorization"))
            let (body, status) = responses[path] ?? ("", 404)
            return (Data(body.utf8), status)
        }
    }

    @Test func usesCreditsAndSkipsKeyWhenCreditsWork() async {
        let calls = CallLog()
        let summary = await loader(["me": (#"{"name":"Ada"}"#, 200), "credits": (#"{"balance":2}"#, 200)], calls: calls).load(token: "tok")
        #expect(summary?.credits?.balance == 2)
        #expect(!calls.paths.contains("key"))
        #expect(calls.auths.allSatisfy { $0 == "Bearer tok" })
    }

    @Test func fallsBackToKeyWhenCreditsAreRejected() async {
        let calls = CallLog()
        let summary = await loader(["me": (#"{"name":"Ada"}"#, 200), "credits": ("{}", 403),
                                    "key": (#"{"data":{"usage":1}}"#, 200)], calls: calls).load(token: "tok")
        #expect(summary?.keyUsage?.usage == 1)
        #expect(calls.paths.contains("key"))
    }

    @Test func returnsNilWhenNothingAnswers() async {
        let summary = await loader([:], calls: CallLog()).load(token: "tok")
        #expect(summary == nil)
    }
}

final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, String?)] = []
    func add(_ path: String, auth: String?) { lock.withLock { entries.append((path, auth)) } }
    var paths: [String] { lock.withLock { entries.map(\.0) } }
    var auths: [String?] { lock.withLock { entries.map(\.1) } }
}
