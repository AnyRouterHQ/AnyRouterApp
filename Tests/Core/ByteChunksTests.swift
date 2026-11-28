import Foundation
import Testing
@testable import AnyRouter

struct ByteChunksTests {
    private func stream(_ text: String) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in text.utf8 { continuation.yield(byte) }
            continuation.finish()
        }
    }

    private func chunks(_ text: String, size: Int, delimiter: UInt8? = nil) async throws -> [String] {
        var out: [String] = []
        try await stream(text).forEachChunk(size: size, endingAt: delimiter) { chunk in
            out.append(String(decoding: chunk, as: UTF8.self))
            return true
        }
        return out
    }

    @Test func cutsAtTheSizeAndKeepsTheRemainder() async throws {
        #expect(try await chunks("abcdefg", size: 3) == ["abc", "def", "g"])
    }

    @Test func aDelimiterEndsTheChunkEarlySoALineIsNotHeldBack() async throws {
        #expect(try await chunks("ab\ncd\n\ne", size: 100, delimiter: 0x0A) == ["ab\n", "cd\n", "\n", "e"])
    }

    @Test func nothingIsLostOrReorderedWhateverTheSize() async throws {
        let text = "data: one\n\ndata: two\r\n\r\n"
        for size in [1, 2, 5, 64] {
            #expect(try await chunks(text, size: size).joined() == text, "size \(size)")
        }
    }

    @Test func stoppingEarlyReadsNoMore() async throws {
        var seen = 0
        try await stream("aaaabbbbcccc").forEachChunk(size: 4) { _ in
            seen += 1
            return false
        }
        #expect(seen == 1)
    }

    @Test func anSSEEventSplitAcrossChunksStillParses() async throws {
        let text = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\ndata: [DONE]\n\n"
        var parser = SSEParser()
        var payloads: [String] = []
        try await stream(text).forEachChunk(size: 7) { chunk in
            payloads += parser.feed(chunk)
            return true
        }
        payloads += parser.finish()
        #expect(payloads == ["{\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}", "[DONE]"])
    }
}
