import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadShareTextTests {
    private func chat() throws -> ThreadRecord {
        let c = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let t = ThreadRecord(title: "Trip to Lisbon")
        c.insert(t)
        let turns: [(ChatMessage.Role, String, String?)] = [
            (.assistant, "Three days is enough.", "GPT-5"), (.user, "Plan a trip", nil),
            (.system, "hidden", nil), (.assistant, "  ", "GPT-5"), (.assistant, "Second try", nil),
        ]
        for (i, turn) in turns.enumerated() {
            let m = MessageRecord(role: turn.0, content: turn.1, createdAt: Date(timeIntervalSince1970: Double(i)), modelName: turn.2)
            c.insert(m)
            m.thread = t
        }
        return t
    }

    @Test func titleThenEachTurnInOrderWithSpeakerNames() throws {
        let text = ThreadShareText.text(for: try chat())
        #expect(text == "# Trip to Lisbon\n\nGPT-5:\nThree days is enough.\n\nYou:\nPlan a trip\n\nAssistant:\nSecond try\n")
    }

    @Test func systemTurnsAndEmptyRepliesAreLeftOut() throws {
        let text = ThreadShareText.text(for: try chat())
        #expect(!text.contains("hidden"))
        #expect(text.components(separatedBy: "GPT-5:").count == 2)
    }

    @Test func fileNameComesFromTheTitle() {
        #expect(ThreadShareText.fileName(for: "Trip to Lisbon!") == "Trip-to-Lisbon.md")
        #expect(ThreadShareText.fileName(for: "a/b: c") == "a-b-c.md")
        #expect(ThreadShareText.fileName(for: "???") == "Chat.md")
        #expect(ThreadShareText.fileName(for: String(repeating: "x", count: 100)).count == 63)
    }

    @Test func theFileHoldsTheTextUnderTheTitleName() throws {
        let url = try ThreadShareText.writeFile(title: "My chat", text: "hello")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.lastPathComponent == "My-chat.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello")
    }
}
