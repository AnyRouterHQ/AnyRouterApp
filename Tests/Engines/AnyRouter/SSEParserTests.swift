import XCTest

@testable import AnyRouter

final class SSEParserTests: XCTestCase {
    private func decodeAll(_ chunks: [String]) throws -> (deltas: [String], decoder: ChatChunkDecoder) {
        var parser = SSEParser()
        var decoder = ChatChunkDecoder()
        var out: [String] = []
        func take(_ payloads: [String]) throws {
            for payload in payloads {
                for delta in try decoder.decode(payload) { out.append(Self.describe(delta)) }
            }
        }
        for chunk in chunks { try take(parser.feed(Data(chunk.utf8))) }
        try take(parser.finish())
        return (out, decoder)
    }

    static func describe(_ delta: ChatDelta) -> String {
        switch delta {
        case .text(let text): return "text:\(text)"
        case .reasoning(let text): return "reasoning:\(text)"
        case .usage(let usage): return "usage:\(usage.input)/\(usage.output)"
        case .done(let reason): return "done:\(reason ?? "nil")"
        case .toolCall(let call): return "toolCall:\(call.name)"
        case .toolResult(let result): return "toolResult:\(result.name)"
        case .metadata(let metadata): return "metadata:\(metadata.servedModelID ?? "nil")"
        }
    }

    private let stream = """
        data: {"id":"c1","choices":[{"delta":{"role":"assistant","content":"Hel"}}]}

        : keep-alive

        data: {"id":"c1","choices":[{"delta":{"content":"lo"},"finish_reason":null}]}

        data: {"id":"c1","choices":[{"delta":{},"finish_reason":"stop"}]}

        data: {"id":"c1","choices":[],"usage":{"prompt_tokens":12,"completion_tokens":3}}

        data: [DONE]


        """

    func testDeltasUsageAndDone() throws {
        let result = try decodeAll([stream])
        XCTAssertEqual(result.deltas, ["text:Hel", "text:lo", "usage:12/3", "done:stop"])
        XCTAssertTrue(result.decoder.isDone)
    }

    func testEventsSplitAcrossReadsAndCRLF() throws {
        let crlf = stream.replacingOccurrences(of: "\n", with: "\r\n")
        // Odd split sizes cut through lines, JSON and the CRLF pairs.
        for size in [1, 2, 3, 7, 13] {
            var chunks: [String] = []
            let bytes = Array(crlf.utf8)
            var index = 0
            while index < bytes.count {
                let end = min(index + size, bytes.count)
                chunks.append(String(decoding: bytes[index..<end], as: UTF8.self))
                index = end
            }
            // Splitting inside a multi-byte scalar is not possible here: the fixture is ASCII.
            let result = try decodeAll(chunks)
            XCTAssertEqual(result.deltas, ["text:Hel", "text:lo", "usage:12/3", "done:stop"], "size \(size)")
        }
    }

    func testFinalEventWithoutBlankLineIsFlushed() throws {
        let result = try decodeAll(["data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}"])
        XCTAssertEqual(result.deltas, ["text:hi"])
        XCTAssertFalse(result.decoder.isDone)
    }

    func testErrorChunkThrowsItsMessage() {
        var decoder = ChatChunkDecoder()
        XCTAssertThrowsError(try decoder.decode(#"{"error":{"message":"Rate limited","code":429}}"#)) { error in
            XCTAssertEqual(error as? AnyRouterError, .stream("Rate limited"))
        }
    }

    func testMidStreamErrorAfterTextKeepsEarlierText() throws {
        var parser = SSEParser()
        var decoder = ChatChunkDecoder()
        var text = ""
        let input = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: {\"error\":{\"message\":\"boom\"}}\n\n"
        do {
            for payload in parser.feed(Data(input.utf8)) {
                for case .text(let piece) in try decoder.decode(payload) { text += piece }
            }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AnyRouterError, .stream("boom"))
        }
        XCTAssertEqual(text, "ok")
    }

    func testUnparseablePayloadIsIgnored() throws {
        var decoder = ChatChunkDecoder()
        XCTAssertTrue(try decoder.decode("not json").isEmpty)
    }
}
