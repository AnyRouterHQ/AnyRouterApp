import Foundation
import Testing
@testable import AnyRouter

struct DecisionRequestEncodingTests {
    private func body(_ request: DecisionRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.jsonBody()) as? [String: Any])
    }

    @Test func eachQuestionKindUsesTheServersWireShape() throws {
        let request = DecisionRequest(model: "anyrouter/decision", state: "Please refund me.", questions: [
            DecisionQuestion(id: "q1", prompt: "Is it urgent?", kind: .yesNo),
            DecisionQuestion(id: "q2", prompt: "Which team?", kind: .choice(options: ["billing", "tech"])),
            DecisionQuestion(id: "q3", prompt: "How polite?", kind: .rubric(levels: ["rude", "neutral", "kind"])),
        ])
        let json = try body(request)
        #expect(json["model"] as? String == "anyrouter/decision")
        #expect(json["state"] as? String == "Please refund me.")
        let questions = try #require(json["questions"] as? [String: [String: Any]])
        #expect(questions["q1"]?["type"] as? String == "noul")
        #expect(questions["q1"]?["instructions"] as? String == "Is it urgent?")
        #expect(questions["q1"]?["criteria"] == nil)
        #expect(questions["q2"]?["type"] as? String == "choice")
        let criteria = try #require(questions["q2"]?["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == ["billing", "tech"])
        #expect(criteria.values.allSatisfy { $0 is NSNull })
        #expect(questions["q3"]?["type"] as? String == "score")
        #expect(questions["q3"]?["criteria"] as? [String] == ["rude", "neutral", "kind"])
    }

    @Test func imagesGoOutAsRawBase64WithoutADataURL() throws {
        let request = DecisionRequest(
            model: "m", state: "s", questions: [DecisionQuestion(id: "q1", prompt: "p", kind: .yesNo)],
            images: [DecisionImage(mediaType: "image/png", data: Data([1, 2, 3]))])
        let text = try #require(String(data: request.jsonBody(), encoding: .utf8))
        #expect(text == ##"{"images":[{"base64":"AQID","mediaType":"image/png"}],"model":"m","questions":{"q1":{"instructions":"p","type":"noul"}},"state":"s"}"##)
        #expect(!text.contains("data:"))
    }

    @Test func noImagesMeansNoImagesKey() throws {
        let request = DecisionRequest(model: "m", state: "s", questions: [DecisionQuestion(id: "q1", prompt: "p", kind: .yesNo)])
        #expect(try body(request)["images"] == nil)
    }

    @Test func theRequestSurvivesAJSONRoundTripForSavedRuns() throws {
        let request = DecisionRequest(model: "m", state: "s", questions: [
            DecisionQuestion(id: "q1", prompt: "p", kind: .choice(options: ["a", "b"]))
        ])
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(DecisionRequest.self, from: data) == request)
    }
}

struct DecisionResponseParsingTests {
    private func request(_ kinds: [DecisionQuestion.Kind]) -> DecisionRequest {
        DecisionRequest(
            model: "anyrouter/decision", state: "s",
            questions: kinds.enumerated().map { DecisionQuestion(id: "q\($0 + 1)", prompt: "Question \($0 + 1)", kind: $1) })
    }

    private func parse(_ json: String, _ kinds: [DecisionQuestion.Kind] = [.yesNo]) throws -> DecisionResult {
        try DecisionResult.parse(Data(json.utf8), for: request(kinds))
    }

    private func answers(_ body: String, usage: String = #"{"input_tokens":3,"output_tokens":4}"#) -> String {
        #"{"model":"jev-latest","answers":\#(body),"usage":\#(usage)}"#
    }

    private func verdict(_ result: DecisionResult, _ index: Int = 0) throws -> DecisionAnswer.Verdict {
        guard case .answered(let verdict) = result.answers[index].outcome else {
            Issue.record("answer \(index) was not answered: \(result.answers[index].outcome)")
            throw TestFailure(message: "not answered")
        }
        return verdict
    }

    // MARK: yes/no

    @Test func yesNoReadsTheProbabilityOfTrue() throws {
        let result = try parse(answers(#"{"q1":{"type":"noul","noul":0.92}}"#))
        let v = try verdict(result)
        #expect(v.headline == "Yes")
        #expect(v.probability == 0.92)
        #expect(v.options == [.init(label: "Yes", probability: 0.92), .init(label: "No", probability: 1 - 0.92)])
        #expect(result.model == "jev-latest")
        #expect(result.inputTokens == 3 && result.outputTokens == 4)
        #expect(result.cost == nil && result.refusal == nil)
    }

    @Test func yesNoBelowHalfIsNoAndATieIsYes() throws {
        #expect(try verdict(parse(answers(#"{"q1":{"type":"noul","noul":0.2}}"#))).headline == "No")
        #expect(try verdict(parse(answers(#"{"q1":{"type":"noul","noul":0.2}}"#))).probability == 1 - 0.2)
        #expect(try verdict(parse(answers(#"{"q1":{"type":"noul","noul":0.5}}"#))).headline == "Yes")
    }

    @Test func probabilitiesAreClampedAndTypeNamesAreCaseInsensitive() throws {
        let v = try verdict(parse(answers(#"{"q1":{"type":"NOUL","noul":1.7}}"#)))
        #expect(v.probability == 1)
    }

    // MARK: choice

    @Test func choiceUsesThePickedOptionAndRanksTheRest() throws {
        let json = answers(#"{"q1":{"type":"choice","choice":"billing","probabilities":{"billing":0.7,"tech":0.2,"other":0.1},"confidence":0.81}}"#)
        let v = try verdict(parse(json, [.choice(options: ["billing", "tech", "other"])]))
        #expect(v.headline == "billing")
        #expect(v.probability == 0.7)
        #expect(v.confidence == 0.81)
        #expect(v.options.map(\.label) == ["billing", "tech", "other"])
    }

    @Test func choiceFallsBackToTheMostLikelyOptionAndBreaksTiesByName() throws {
        let json = answers(#"{"q1":{"type":"choice","choice":"","probabilities":{"b":0.5,"a":0.5,"c":"x"}}}"#)
        let v = try verdict(parse(json, [.choice(options: ["a", "b"])]))
        #expect(v.headline == "a")
        #expect(v.options.map(\.label) == ["a", "b"])
    }

    @Test func aChoiceWithNothingToPickIsUnreadable() throws {
        let result = try parse(answers(#"{"q1":{"type":"choice"}}"#), [.choice(options: ["a", "b"])])
        #expect(result.answers[0].outcome == .unreadable)
    }

    @Test func aPickedOptionWithoutAProbabilityHasNoPercentage() throws {
        let v = try verdict(parse(answers(#"{"q1":{"type":"choice","choice":"z","probabilities":{"a":0.4}}}"#), [.choice(options: ["a", "z"])]))
        #expect(v.headline == "z")
        #expect(v.probability == nil)
    }

    @Test func confidenceOutsideZeroToOneIsIgnored() throws {
        let v = try verdict(parse(answers(#"{"q1":{"type":"choice","choice":"a","probabilities":{"a":1},"confidence":4}}"#), [.choice(options: ["a", "b"])]))
        #expect(v.confidence == nil)
    }

    // MARK: rubric

    @Test func aScoreBetweenLevelsNamesBothLevels() throws {
        let json = answers(#"{"q1":{"type":"score","score":3.4,"legend":{"3":"Good","4":"Great"},"probabilities":{"3":0.6,"4":0.4}}}"#)
        let v = try verdict(parse(json, [.rubric(levels: ["a", "b", "c", "d", "e"])]))
        #expect(v.headline == "3.4")
        #expect(v.score == 3.4)
        #expect(v.maxScore == 4)
        #expect(v.note == "Good to Great")
        #expect(v.probability == nil)
        #expect(v.options == [.init(label: "Good", probability: 0.6), .init(label: "Great", probability: 0.4)])
    }

    @Test func aWholeScoreUsesTheRubricLevelWhenTheServerSendsNoLegend() throws {
        let v = try verdict(parse(answers(#"{"q1":{"type":"score","score":2}}"#), [.rubric(levels: ["rude", "neutral", "kind"])]))
        #expect(v.headline == "2")
        #expect(v.note == "kind")
        #expect(v.maxScore == 2)
        #expect(v.options.isEmpty)
    }

    @Test func scoreFormattingDropsTrailingZeros() throws {
        let levels: [DecisionQuestion.Kind] = [.rubric(levels: ["a", "b", "c", "d"])]
        #expect(try verdict(parse(answers(#"{"q1":{"type":"score","score":2.5}}"#), levels)).headline == "2.5")
        #expect(try verdict(parse(answers(#"{"q1":{"type":"score","score":2.25}}"#), levels)).headline == "2.25")
    }

    @Test func withoutLabelsAScoreHasNoNoteAndOptionsAreNamedByLevel() throws {
        let json = answers(#"{"q1":{"type":"score","score":1.5,"probabilities":{"2":0.3,"1":0.7,"x":0.1}}}"#)
        let v = try verdict(parse(json, [.yesNo]))
        #expect(v.note == nil)
        #expect(v.options.map(\.label) == ["Level 1", "Level 2"])
        #expect(v.maxScore == 2)
    }

    @Test func aWholeScoreWithoutALabelHasNoNote() throws {
        let v = try verdict(parse(answers(#"{"q1":{"type":"score","score":7}}"#), [.rubric(levels: ["a", "b"])]))
        #expect(v.note == nil)
        #expect(v.maxScore == 7)
    }

    @Test func scoresThatAreNotLevelNumbersAreUnreadable() throws {
        for score in ["true", "5000", "-1", #""high""#, "null"] {
            let result = try parse(answers(#"{"q1":{"type":"score","score":\#(score)}}"#), [.rubric(levels: ["a", "b"])])
            #expect(result.answers[0].outcome == .unreadable, "score \(score)")
        }
    }

    // MARK: refusals and gaps

    @Test func anAnswerLevelRefusalIsKeptWithItsReason() throws {
        let result = try parse(answers(#"{"q1":{"type":"noul","refusal":" Cannot judge this. "}}"#))
        #expect(result.answers[0].outcome == .refused("Cannot judge this."))
    }

    @Test func aWholeRequestRefusalRefusesEveryQuestionWithoutAnswers() throws {
        let result = try parse(#"{"model":"m","refusal":"Not allowed","usage":{"input_tokens":1,"output_tokens":0}}"#, [.yesNo, .yesNo])
        #expect(result.refusal == "Not allowed")
        #expect(result.answers.map(\.outcome) == [.refused("Not allowed"), .refused("Not allowed")])
    }

    @Test func aTopLevelRefusalDoesNotHideAnswersThatCameBack() throws {
        let result = try parse(#"{"refusal":"partial","answers":{"q1":{"type":"noul","noul":0.9}},"usage":{}}"#, [.yesNo, .yesNo])
        #expect(result.refusal == "partial")
        #expect(try verdict(result, 0).headline == "Yes")
        #expect(result.answers[1].outcome == .refused("partial"))
    }

    @Test func aMissingAnswerIsUnreadableNotInvented() throws {
        let result = try parse(answers(#"{"q1":{"type":"noul","noul":0.9}}"#), [.yesNo, .yesNo])
        #expect(result.answers[1].outcome == .unreadable)
    }

    @Test func unknownOrMalformedAnswersAreUnreadable() throws {
        let result = try parse(answers(#"{"q1":{"type":"matrix"},"q2":{"noul":0.9},"q3":{"type":"noul"},"q4":"yes"}"#), [.yesNo, .yesNo, .yesNo, .yesNo])
        #expect(result.answers.map(\.outcome) == [.unreadable, .unreadable, .unreadable, .unreadable])
    }

    @Test func aBodyWithNeitherAnswersNorARefusalIsABadResponse() {
        #expect(throws: AnyRouterError.badResponse) { try parse(#"{"model":"m"}"#) }
        #expect(throws: AnyRouterError.badResponse) { try parse("not json") }
        #expect(throws: AnyRouterError.badResponse) { try parse("[1]") }
    }

    // MARK: metadata

    @Test func costAndTokensComeFromUsageAndTheModelFallsBackToTheRequest() throws {
        let result = try parse(#"{"answers":{},"usage":{"input_tokens":10,"output_tokens":2,"cost":0.0012}}"#)
        #expect(result.cost == 0.0012)
        #expect(result.inputTokens == 10 && result.outputTokens == 2)
        #expect(result.model == "anyrouter/decision")
        let bare = try parse(#"{"answers":{}}"#)
        #expect(bare.inputTokens == 0 && bare.outputTokens == 0 && bare.cost == nil)
    }

    @Test func freeRunsReportZeroCost() throws {
        #expect(try parse(#"{"answers":{},"usage":{"cost":0}}"#).cost == 0)
    }

    @Test func citationsAcceptStringsAndObjects() throws {
        let json = answers(#"{"q1":{"type":"noul","noul":0.9,"citations":["https://a.example",{"url":"https://b.example","title":"B"},{"title":"Only title"},{"x":1},7]},"q2":{"type":"noul","noul":0.9,"citations":"nope"}}"#)
        let result = try parse(json, [.yesNo, .yesNo])
        #expect(result.answers[0].citations == ["https://a.example", "https://b.example", "Only title"])
        #expect(result.answers[1].citations.isEmpty)
    }

    @Test func aResultSurvivesAJSONRoundTripForSavedRuns() throws {
        let result = try parse(answers(#"{"q1":{"type":"noul","noul":0.9}}"#))
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(DecisionResult.self, from: data) == result)
    }
}

struct AnyRouterEngineDecisionTests {
    private let ok = #"{"model":"anyrouter/decision","answers":{"q1":{"type":"noul","noul":0.9}},"usage":{"input_tokens":5,"output_tokens":1,"cost":0}}"#
    private let request = DecisionRequest(
        model: "anyrouter/decision", state: "text", questions: [DecisionQuestion(id: "q1", prompt: "Urgent?", kind: .yesNo)])

    @Test func runPostsTheRequestWithTheKeyAndParsesTheAnswer() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let api = StubbedAPI { http in
            seen.value = http
            return StubRegistry.Reply(status: 200, body: Data(ok.utf8))
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        let result = try await engine.runDecision(request)

        let http = try #require(seen.value)
        #expect(http.httpMethod == "POST")
        #expect(http.url?.path == "/api/v1/decisions")
        #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ar-1")
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(http.value(forHTTPHeaderField: "X-AnyRouter-Title") == "AnyRouter for iOS")
        #expect(result.answers.count == 1)
        #expect(result.cost == 0)
        #expect(result.latency >= 0)
    }

    @Test func signedOutNeverSendsARequest() async {
        let sent = Flag()
        let api = StubbedAPI { _ in
            sent.value = true
            return StubRegistry.Reply(status: 200, body: Data(ok.utf8))
        }
        let engine = AnyRouterEngine(tokens: FakeTokens(nil), config: api.config, session: api.session)
        await #expect(throws: AnyRouterError.signedOut) { try await engine.runDecision(request) }
        #expect(!sent.value)
    }

    @Test func aRejectedKeyIsClearedAndReportedAsSignedOut() async {
        let tokens = FakeTokens("sk-ar-old")
        let notified = Flag()
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 401, body: Data()) }
        let engine = AnyRouterEngine(tokens: tokens, config: api.config, session: api.session) { notified.value = true }
        await #expect(throws: AnyRouterError.signedOut) { try await engine.runDecision(request) }
        #expect(tokens.token() == nil)
        #expect(notified.value)
    }

    @Test func aServerErrorKeepsItsMessage() async {
        let api = StubbedAPI { _ in
            StubRegistry.Reply(status: 400, body: Data(#"{"error":{"message":"Question \"q1\" must be an object definition."}}"#.utf8))
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        await #expect(throws: AnyRouterError.http(status: 400, message: #"Question "q1" must be an object definition."#)) {
            try await engine.runDecision(request)
        }
    }

    @Test func aRefusedPhotoIsATypedErrorAndAnyOther400StaysHTTP() async {
        let refused = StubbedAPI { _ in
            StubRegistry.Reply(status: 400, body: Data(##"{"error":{"message":"bad image","code":"invalid_images"}}"##.utf8))
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: refused.config, session: refused.session)
        await #expect(throws: DecisionRunError.imagesRefused(serverMessage: "bad image")) { try await engine.runDecision(request) }
        #expect(DecisionRunError.imagesRefused(serverMessage: "x").errorDescription == "This model can't read photos. Choose another model.")
        #expect(!DecisionRunError.isImageRejection(Data("nope".utf8)))
        #expect(!DecisionRunError.isImageRejection(Data(##"{"error":{"code":"invalid_questions"}}"##.utf8)))
    }

    @Test func aSuccessBodyThatIsNotADecisionIsABadResponse() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 200, body: Data("<html>".utf8)) }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        await #expect(throws: AnyRouterError.badResponse) { try await engine.runDecision(request) }
    }
}
