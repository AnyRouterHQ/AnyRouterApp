import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct CoreGapTests {
    @Test func aSourceWithoutAnEngineListsNothingAndSaysWhy() async throws {
        let engine = EngineRegistry().engine(for: descriptor("gguf/r/f", .gguf))
        #expect(try await engine.availableModels().isEmpty)
        #expect(EngineNotRegisteredError(source: .gguf).errorDescription == "No engine registered for gguf.")
    }

    @Test func changingAMessageRoleUpdatesWhatIsStored() {
        let record = MessageRecord(role: .user, content: "x")
        record.role = .system
        #expect(record.roleRaw == "system")
        #expect(record.chatMessage.role == .system)
    }
}
