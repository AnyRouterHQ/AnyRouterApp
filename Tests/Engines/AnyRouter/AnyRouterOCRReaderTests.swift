import Foundation
import Testing
@testable import AnyRouter

struct AnyRouterOCRWireTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2])

    @Test func theTypeComesFromTheFirstBytes() {
        #expect(AnyRouterOCRWire.mimeType(of: png) == "image/png")
        #expect(AnyRouterOCRWire.mimeType(of: Data("%PDF-1.7".utf8)) == "application/pdf")
        #expect(AnyRouterOCRWire.mimeType(of: Data("GIF89a".utf8)) == "image/gif")
        #expect(AnyRouterOCRWire.mimeType(of: Data("RIFF0000WEBPVP8 ".utf8)) == "image/webp")
        #expect(AnyRouterOCRWire.mimeType(of: Data("RIFF0000WAVEfmt ".utf8)) == "image/jpeg")
        #expect(AnyRouterOCRWire.mimeType(of: Data([0xFF, 0xD8, 0xFF])) == "image/jpeg")
        #expect(AnyRouterOCRWire.mimeType(of: Data()) == "image/jpeg")
    }

    @Test func theBodyHoldsADataURLAndTheFilename() throws {
        let body = try AnyRouterOCRWire.body(image: png, filename: "receipt.png")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["image"] == "data:image/png;base64,\(png.base64EncodedString())")
        #expect(json["filename"] == "receipt.png")
        let bare = try AnyRouterOCRWire.body(image: png, filename: nil)
        let bareJSON = try #require(try JSONSerialization.jsonObject(with: bare) as? [String: String])
        #expect(Set(bareJSON.keys) == ["image"])
    }

    @Test func fiveMebibytesIsTheMostThatIsSent() throws {
        #expect(AnyRouterOCRWire.maxBytes == 5_242_880)
        _ = try AnyRouterOCRWire.body(image: Data(count: 5_242_880), filename: nil)
        #expect(throws: AnyRouterOCRError.tooLarge) { try AnyRouterOCRWire.body(image: Data(count: 5_242_881), filename: nil) }
        #expect(AnyRouterOCRError.tooLarge.errorDescription?.contains("5 MB") == true)
    }

    @Test func theAnswerIsItsMarkdownText() throws {
        let answer = ##"{"text":"# Cafe\n| a | b |","format":"markdown","tokens":12}"##
        #expect(try AnyRouterOCRWire.imageText(from: Data(answer.utf8)) == ImageText(text: "# Cafe\n| a | b |"))
        #expect(throws: AnyRouterError.badResponse) { try AnyRouterOCRWire.imageText(from: Data("<html>".utf8)) }
        #expect(throws: AnyRouterError.badResponse) { try AnyRouterOCRWire.imageText(from: Data(##"{"format":"markdown"}"##.utf8)) }
    }
}

struct AnyRouterOCRReaderTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    private let ok = ##"{"text":"CAFE 12\nTotal 5.00","format":"markdown","tokens":9}"##

    private func reader(_ api: StubbedAPI, tokens: FakeTokens, onUnauthorized: @escaping @Sendable () async -> Void = {}) -> AnyRouterOCRReader {
        AnyRouterOCRReader(
            engine: AnyRouterEngine(tokens: tokens, config: api.config, session: api.session, onUnauthorized: onUnauthorized),
            filename: "receipt.png")
    }

    private func bytes(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    @Test func aReadPostsTheImageWithTheKeyAndReturnsTheText() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let sentBody = LockedBox<Data>(Data())
        let api = StubbedAPI { http in
            seen.value = http
            sentBody.value = bytes(of: http)
            return StubRegistry.Reply(status: 200, body: Data(ok.utf8))
        }
        let read = try await reader(api, tokens: FakeTokens("sk-ar-1")).read(png)

        #expect(read.text == "CAFE 12\nTotal 5.00")
        let http = try #require(seen.value)
        #expect(http.httpMethod == "POST")
        #expect(http.url?.path == "/api/v1/ocr/extract")
        #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ar-1")
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try #require(try JSONSerialization.jsonObject(with: sentBody.value) as? [String: String])
        #expect(json["image"] == "data:image/png;base64,\(png.base64EncodedString())")
        #expect(json["filename"] == "receipt.png")
    }

    @Test func aTooLargeImageNeverLeavesTheDevice() async {
        let sent = Flag()
        let api = StubbedAPI { _ in
            sent.value = true
            return StubRegistry.Reply(status: 200, body: Data(ok.utf8))
        }
        await #expect(throws: AnyRouterOCRError.tooLarge) {
            try await reader(api, tokens: FakeTokens("sk-ar-1")).read(Data(count: AnyRouterOCRWire.maxBytes + 1))
        }
        #expect(!sent.value)
    }

    @Test func signedOutNeverSendsARequest() async {
        let sent = Flag()
        let api = StubbedAPI { _ in
            sent.value = true
            return StubRegistry.Reply(status: 200, body: Data(ok.utf8))
        }
        await #expect(throws: AnyRouterError.signedOut) { try await reader(api, tokens: FakeTokens(nil)).read(png) }
        #expect(!sent.value)
    }

    @Test func aRejectedKeyIsClearedAndReportedAsSignedOut() async {
        let tokens = FakeTokens("sk-ar-old")
        let notified = Flag()
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 401, body: Data()) }
        await #expect(throws: AnyRouterError.signedOut) {
            try await reader(api, tokens: tokens) { notified.value = true }.read(png)
        }
        #expect(tokens.token() == nil)
        #expect(notified.value)
    }

    @Test func aServerThatSays413IsTooLarge() async {
        let tokens = FakeTokens("sk-ar-1")
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 413, body: Data()) }
        await #expect(throws: AnyRouterOCRError.tooLarge) { try await reader(api, tokens: tokens).read(png) }
        #expect(tokens.token() == "sk-ar-1")
    }

    @Test func otherFailuresKeepTheirMessage() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 500, body: Data(##"{"error":{"message":"Reader is down."}}"##.utf8)) }
        await #expect(throws: AnyRouterError.http(status: 500, message: "Reader is down.")) {
            try await reader(api, tokens: FakeTokens("sk-ar-1")).read(png)
        }
    }

    @Test func aSuccessThatIsNotAnAnswerIsABadResponse() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 200, body: Data("<html>".utf8)) }
        await #expect(throws: AnyRouterError.badResponse) { try await reader(api, tokens: FakeTokens("sk-ar-1")).read(png) }
    }
}
