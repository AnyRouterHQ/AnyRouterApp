import Foundation
import Testing
@testable import AnyRouter

struct MarkdownImagesTests {
    /// An image URL can carry words of the conversation, so no remote image may ever be requested while a reply renders.
    @Test func inlineImagesAreNeverLoaded() async {
        let url = URL(string: "https://example.com/pixel.png?leak=secret")!
        await #expect(throws: BlockedInlineImageProvider.Blocked.self) {
            _ = try await BlockedInlineImageProvider().image(with: url, label: "x")
        }
    }
}
