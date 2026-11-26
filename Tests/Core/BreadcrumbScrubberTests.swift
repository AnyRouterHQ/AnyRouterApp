import Foundation
import Testing
@testable import AnyRouter

struct BreadcrumbScrubberTests {
    @Test func urlQueryAndFragmentAreRemoved() {
        #expect(BreadcrumbScrubber.scrub("GET https://anyrouter.dev/api/v1/models?key=sk-123&x=1 done")
            == "GET https://anyrouter.dev/api/v1/models done")
        #expect(BreadcrumbScrubber.scrub("callback http://127.0.0.1:8080/cb#access_token=abc") == "callback http://127.0.0.1:8080/cb")
    }

    @Test func urlsWithoutQueryAndPlainTextAreUntouched() {
        #expect(BreadcrumbScrubber.scrub("https://anyrouter.dev/docs") == "https://anyrouter.dev/docs")
        #expect(BreadcrumbScrubber.scrub("model loaded") == "model loaded")
        #expect(BreadcrumbScrubber.scrub("what? really") == "what? really", "a question mark outside a URL is not a query")
    }

    @Test func everyUrlInATextIsScrubbed() {
        #expect(BreadcrumbScrubber.scrub("a https://x.io/a?q=1 b https://y.io/b?r=2")
            == "a https://x.io/a b https://y.io/b")
    }

    @Test func bearerTokensAreRedacted() {
        #expect(BreadcrumbScrubber.scrub("Authorization: Bearer abc.DEF-123_x") == "Authorization: Bearer [redacted]")
        #expect(BreadcrumbScrubber.scrub("bearer tok") == "Bearer [redacted]")
    }

    @Test func dataValuesAreScrubbedByType() {
        let url = URL(string: "https://anyrouter.dev/cb?code=1")!
        let scrubbed = BreadcrumbScrubber.scrub(data: [
            "text": "https://a.io/p?token=1", "url": url, "count": 3, "flag": true,
        ])
        #expect(scrubbed?["text"] as? String == "https://a.io/p")
        #expect(scrubbed?["url"] as? String == "https://anyrouter.dev/cb")
        #expect(scrubbed?["count"] as? Int == 3)
        #expect(scrubbed?["flag"] as? Bool == true)
        #expect(BreadcrumbScrubber.scrub(data: nil) == nil)
    }
}
