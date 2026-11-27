import Foundation
import Testing
import UIKit
@testable import AnyRouter

/// A failed reply says what happened in one plain sentence and offers the one action that helps.
struct ReplyFailureLogicTests {
    private func kind(_ error: any Error) -> ReplyFailure.Kind { ReplyFailureLogic.kind(of: error) }

    @Test func noConnectionAndATimeoutAreToldApart() {
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed] {
            #expect(kind(URLError(code)) == .offline, "\(code)")
        }
        #expect(kind(URLError(.timedOut)) == .timeout)
        #expect(kind(URLError(.cancelled)) == .cancelled)
        #expect(kind(URLError(.userAuthenticationRequired)) == .signedOut)
        #expect(kind(URLError(.badServerResponse)) == .unknown)
        #expect(kind(CancellationError()) == .cancelled)
    }

    @Test func anyRouterStatusCodesMapToWhatThePersonCanDo() {
        #expect(kind(AnyRouterError.signedOut) == .signedOut)
        #expect(kind(AnyRouterError.badResponse) == .unknown)
        let cases: [(Int, ReplyFailure.Kind)] = [
            (401, .signedOut), (402, .outOfCredits), (404, .modelUnavailable), (408, .timeout), (504, .timeout),
            (413, .contextTooLong), (429, .rateLimited), (500, .modelUnavailable), (503, .modelUnavailable),
        ]
        for (status, expected) in cases {
            #expect(kind(AnyRouterError.http(status: status, message: "x")) == expected, "HTTP \(status)")
        }
        // A 400 says what is wrong only in words.
        #expect(kind(AnyRouterError.http(status: 400, message: "This model's maximum context length is 8192 tokens")) == .contextTooLong)
        #expect(kind(AnyRouterError.http(status: 400, message: "Bad request")) == .unknown)
        #expect(kind(AnyRouterError.stream("Rate limit exceeded, retry later")) == .rateLimited)
    }

    @Test func theWordsOfAnErrorDecideWhenNothingElseDoes() {
        #expect(ReplyFailureLogic.kind(ofText: "Exceeded the context window") == .contextTooLong)
        #expect(ReplyFailureLogic.kind(ofText: "The context size was exceeded.") == .contextTooLong)
        #expect(ReplyFailureLogic.kind(ofText: "Too Many Requests") == .rateLimited)
        #expect(ReplyFailureLogic.kind(ofText: "Insufficient credits") == .outOfCredits)
        #expect(ReplyFailureLogic.kind(ofText: "The request timed out.") == .timeout)
        #expect(ReplyFailureLogic.kind(ofText: "boom") == .unknown)
        #expect(kind(TestFailure(message: "upstream: rate limit hit")) == .rateLimited)
    }

    @Test func onDeviceModelsTellMemoryFromALoadFailure() {
        #expect(kind(GGUFError.wontFit(name: "m", neededBytes: 9, availableBytes: 1)) == .localOutOfMemory)
        #expect(kind(GGUFError.imagesWontFit(name: "m", neededBytes: 9, availableBytes: 1)) == .localOutOfMemory)
        #expect(kind(GGUFError.contextFailed) == .localOutOfMemory)
        #expect(kind(GGUFError.loadFailed(name: "m", reason: nil)) == .localLoadFailed)
        #expect(kind(GGUFError.modelNotInstalled("m")) == .localLoadFailed)
        #expect(kind(GGUFError.projectorLoadFailed("m")) == .localLoadFailed)
        #expect(kind(GGUFError.promptTooLong(tokens: 9000, limit: 4096)) == .contextTooLong)
        #expect(kind(GGUFError.imagesNotSupported("m")) == .modelUnavailable)
        for error in [GGUFError.tokenizeFailed, .decodeFailed(-1), .imageUnreadable, .imageEncodeFailed(2)] {
            #expect(kind(error) == .unknown)
        }
        #expect(kind(MLXError.unavailable("no Metal")) == .localLoadFailed)
        #expect(kind(MLXError.modelNotInstalled("m")) == .localLoadFailed)
        #expect(kind(MLXError.emptyConversation) == .unknown)
        #expect(kind(AppleFoundationEngine.Failure.unavailable("off")) == .modelUnavailable)
        #expect(kind(AppleFoundationEngine.Failure.emptyPrompt) == .unknown)
    }

    @Test func aToolServerErrorIsAToolFailure() {
        #expect(kind(MCPError.transport("socket closed")) == .toolFailed)
        #expect(kind(MCPError.unauthorized) == .toolFailed)
    }

    @Test func theRawTextIsKeptAsTheDetail() {
        let failure = ReplyFailureLogic.classify(AnyRouterError.http(status: 402, message: "Insufficient credits: 0.00 left"))
        #expect(failure == ReplyFailure(kind: .outOfCredits, detail: "Insufficient credits: 0.00 left"))
    }

    @Test func eachKindHasASentenceAndASymbolTheSystemKnows() {
        let sentences = ReplyFailure.Kind.allCases.map(ReplyFailureLogic.message)
        #expect(Set(sentences).count == ReplyFailure.Kind.allCases.count, "no two kinds read the same")
        for kind in ReplyFailure.Kind.allCases {
            #expect(!ReplyFailureLogic.message(for: kind).isEmpty)
            #expect(UIImage(systemName: ReplyFailureLogic.symbol(for: kind)) != nil, "\(kind)")
        }
    }

    @Test func theFixComesFirstAndRetryFollowsOnlyWhileTheReplyCanBeRetried() {
        #expect(ReplyFailureLogic.actions(for: .offline, canRetry: true) == [.retry])
        #expect(ReplyFailureLogic.actions(for: .offline, canRetry: false) == [])
        #expect(ReplyFailureLogic.actions(for: .signedOut, canRetry: true) == [.signIn, .retry])
        #expect(ReplyFailureLogic.actions(for: .signedOut, canRetry: false) == [.signIn])
        #expect(ReplyFailureLogic.actions(for: .contextTooLong, canRetry: true).first == .shortenChat)
        #expect(ReplyFailureLogic.actions(for: .contextTooLong, canRetry: true, canAskCloud: true) == [.shortenChat, .retry, .askCloudModel])
        #expect(ReplyFailureLogic.actions(for: .localOutOfMemory, canRetry: false, canAskCloud: true) == [.chooseModel, .askCloudModel])
        #expect(ReplyFailureLogic.actions(for: .offline, canRetry: true, canAskCloud: true) == [.retry], "a cloud model needs the connection too")
        #expect(ReplyFailureLogic.title(of: .askCloudModel) == "Ask a cloud model")
        #expect(ReplyFailureLogic.actions(for: .localLoadFailed, canRetry: true).first == .openSettings)
        for kind: ReplyFailure.Kind in [.outOfCredits, .modelUnavailable, .localOutOfMemory] {
            #expect(ReplyFailureLogic.actions(for: kind, canRetry: true) == [.chooseModel, .retry])
        }
        for kind: ReplyFailure.Kind in [.timeout, .rateLimited, .toolFailed, .cancelled, .unknown, .interrupted] {
            #expect(ReplyFailureLogic.actions(for: kind, canRetry: true) == [.retry])
        }
        let titles = [ReplyFailure.Action.retry, .signIn, .chooseModel, .shortenChat, .openSettings].map(ReplyFailureLogic.title)
        #expect(titles == ["Retry", "Sign in", "Choose another model", "Shorten chat", "Open Local Models"])
    }

    @Test func aStoredFailureReadsBackAndAnUnknownKindIsNotLost() throws {
        let failure = ReplyFailure(kind: .rateLimited, detail: "slow down")
        let data = try JSONEncoder().encode(failure)
        #expect(try JSONDecoder().decode(ReplyFailure.self, from: data) == failure)
        // Saved by a newer build with a kind this one does not know.
        let newer = Data(#"{"kind":"solarFlare","detail":"x"}"#.utf8)
        #expect(try JSONDecoder().decode(ReplyFailure.self, from: newer) == ReplyFailure(kind: .unknown, detail: "x"))
    }
}
