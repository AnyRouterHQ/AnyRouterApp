import Foundation
import Testing
import UIKit
@testable import AnyRouter

struct DecisionAppsLogicTests {
    private func apps() throws -> [DecisionApp] { try DecisionAppsLogic.load() }

    private func app(_ questions: [DecisionApp.Question], line: String = "{a}") -> DecisionApp {
        DecisionApp(id: "t", title: "T", symbol: "star", inputHint: "h", acceptsImages: true, preferredModel: "x/first", fallbackModel: "x/second",
                    samples: [], questions: questions, resultLine: line)
    }

    private func yesNo(_ id: String = "a") -> DecisionApp.Question { .init(id: id, prompt: "Is it?", type: .yesNo) }

    private func verdict(_ headline: String, score: Double? = nil, max: Double? = nil, note: String? = nil) -> DecisionAnswer.Outcome {
        .answered(.init(headline: headline, probability: nil, score: score, maxScore: max, note: note, options: []))
    }

    private func result(_ answers: [DecisionAnswer], refusal: String? = nil) -> DecisionResult {
        DecisionResult(model: "m", answers: answers, inputTokens: 0, outputTokens: 0, cost: 0, refusal: refusal, latency: 0)
    }

    private func answer(_ id: String, _ outcome: DecisionAnswer.Outcome) -> DecisionAnswer {
        DecisionAnswer(id: id, prompt: "Question \(id)?", outcome: outcome, citations: [])
    }

    // MARK: Catalog

    @Test func theBundledCatalogHasTheStarterAppsAndPasteInOrder() throws {
        #expect(try apps().map(\.id) == [
            "email-triage", "receipt-sort", "traffic-sign", "incident-triage", "policy-check", "tone-check", "paste",
        ])
        #expect(try Set(apps().map(\.id)).count == 7)
        #expect(try apps().allSatisfy { !$0.samples.isEmpty })
    }

    /// A blank tile is the only sign of a misspelled symbol, so every app's symbol must exist.
    @Test func everyAppSymbolIsAnSFSymbol() throws {
        for app in try apps() {
            #expect(UIImage(systemName: app.symbol) != nil, "\(app.id): \(app.symbol)")
        }
    }

    // MARK: Traffic sign

    private func trafficSign() throws -> DecisionApp { try #require(try apps().first { $0.id == "traffic-sign" }) }

    /// The photo is the input: photos come first, a model that can read them is picked, and text is optional.
    @Test func theTrafficSignAppIsPhotoFirstWithTypedQuestions() throws {
        let sign = try trafficSign()
        #expect(DecisionAppsLogic.problem(with: sign) == nil)
        #expect(sign.acceptsImages && sign.photoFirst == true && sign.preferredModel == "google/gemini-decision-1")
        #expect(sign.questions.map(\.id) == ["kind", "sign", "speed", "cars"])
        #expect(sign.questions.map(\.type) == [.choice, .choice, .choice, .yesNo])
        for question in sign.questions where question.type != .yesNo {
            #expect(!question.list.isEmpty && Set(question.list).count == question.list.count, "\(question.id)")
        }
        let kinds = sign.questions[0].list
        #expect(kinds.contains("not a traffic sign") && kinds.contains("priority (stop or yield)"))
        let signs = sign.questions[1].list
        #expect(["stop", "give way or yield", "no entry", "speed limit", "end of speed limit", "other"].allSatisfy { signs.contains($0) })
        #expect(sign.questions[2].list == ["none", "20", "30", "40", "50", "60", "70", "80", "90", "100", "120"])
    }

    /// A photo with no text goes out as the photo plus the fixed line, with all four questions.
    @Test func aTrafficSignPhotoAloneBuildsTheRequest() throws {
        let photo = DecisionImage(mediaType: "image/jpeg", data: Data([1, 2, 3]))
        let request = try #require(DecisionAppsLogic.request(try trafficSign(), model: "google/gemini-decision-1", state: "", images: [photo]))
        #expect(request.state == DecisionsLogic.photoOnlyState)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonBody()) as? [String: Any])
        let images = try #require(json["images"] as? [[String: String]])
        #expect(images == [["mediaType": "image/jpeg", "base64": "AQID"]])
        let questions = try #require(json["questions"] as? [String: [String: Any]])
        #expect(Set(questions.keys) == ["kind", "sign", "speed", "cars"])
        let speed = try #require(questions["speed"]?["criteria"] as? [String: Any])
        #expect(speed.count == 11)
    }

    /// The result names only what the answers say: the sign, its kind, the number on it and who it is for.
    @Test func theTrafficSignResultLineSaysOnlyWhatTheSignSays() throws {
        let line = DecisionAppsLogic.resultLine(try trafficSign(), result: result([
            answer("kind", verdict("regulatory or prohibitory")),
            answer("sign", verdict("speed limit")),
            answer("speed", verdict("50")),
            answer("cars", verdict("Yes")),
        ]))
        #expect(line == "Sign: speed limit, regulatory or prohibitory. Speed limit shown: 50. It applies to cars.")
    }

    @Test func everyAppBuildsARequestTheServerAccepts() throws {
        for app in try apps() {
            #expect(DecisionAppsLogic.problem(with: app) == nil, "\(app.id)")
            let request = try #require(DecisionAppsLogic.request(app, model: "anyrouter/decision", state: app.samples[0].text, images: []))
            let json = try #require(JSONSerialization.jsonObject(with: request.jsonBody()) as? [String: Any])
            let questions = try #require(json["questions"] as? [String: [String: Any]])
            #expect(questions.count == app.questions.count)
            for question in app.questions {
                let wire = try #require(questions[question.id])
                switch question.type {
                case .yesNo: #expect(wire["type"] as? String == "noul" && wire["criteria"] == nil)
                case .choice:
                    let criteria = try #require(wire["criteria"] as? [String: Any])
                    #expect(criteria.count == question.list.count && !criteria.isEmpty)
                case .score:
                    let levels = try #require(wire["criteria"] as? [String])
                    #expect((2...10).contains(levels.count))
                }
            }
        }
    }

    @Test func aMissingBundleFileThrows() throws {
        let empty = try #require(Bundle(path: NSTemporaryDirectory()))
        #expect(throws: CocoaError.self) { try DecisionAppsLogic.load(bundle: empty) }
    }

    // MARK: Validity rules

    @Test func eachValidityRuleIsChecked() {
        let choice = DecisionApp.Question(id: "a", prompt: "Which?", type: .choice, items: ["x", "y"])
        #expect(DecisionAppsLogic.problem(with: app([choice])) == nil)
        #expect(DecisionAppsLogic.problem(with: app([])) == "t has no questions.")
        #expect(DecisionAppsLogic.problem(with: app([yesNo(), yesNo()])) == "t repeats a question id.")
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: " ", type: .yesNo)])) == "a has no prompt.")
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .yesNo, items: ["x"])])) == "a is yes/no and takes no items.")
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .choice, items: ["x"])])) == "a needs two or more distinct options.")
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .choice, items: ["x", "x"])])) == "a needs two or more distinct options.")
        let eleven = (0..<11).map(String.init)
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .score, items: eleven)])) == "a needs 2 to 10 levels.")
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .score, items: Array(eleven.prefix(10)))])) == nil)
        #expect(DecisionAppsLogic.problem(with: app([.init(id: "a", prompt: "p", type: .score)])) == "a needs 2 to 10 levels.")
        #expect(DecisionAppsLogic.problem(with: app([yesNo()], line: "{b}")) == "t has a result line with a missing question id.")
        #expect(DecisionAppsLogic.problem(with: app([yesNo()], line: "no tokens")) == "t has a result line with a missing question id.")
        #expect(DecisionAppsLogic.problem(with: app([yesNo()], line: "{a} and {broken")) == nil)
    }

    @Test func aBrokenAppNeverBuildsARequest() {
        #expect(DecisionAppsLogic.request(app([]), model: "m", state: "text", images: []) == nil)
        #expect(DecisionAppsLogic.blocker(app([yesNo()]), model: "m", state: "", images: []) == "Add something to judge.")
        #expect(DecisionAppsLogic.blocker(app([yesNo()]), model: "m", state: "t", images: []) == nil)
    }

    @Test func aPhotoOnlyRunSendsTheFixedText() throws {
        let image = DecisionImage(mediaType: "image/jpeg", data: Data([1]))
        let request = try #require(DecisionAppsLogic.request(app([yesNo()]), model: "m", state: "", images: [image]))
        #expect(request.state == DecisionsLogic.photoOnlyState && request.images == [image])
    }

    // MARK: Photos and models

    /// A decision model reads photos only when the catalog says its input takes images; nothing chosen yet still lets a
    /// photo be added first.
    @Test func photosShowForPhotoAppsAndModelsThatReadThem() {
        var see = testModel(id: "anyrouter/x/see", source: .anyrouter)
        see.capabilities = ["decision", "vision"]
        var text = testModel(id: "anyrouter/x/text", source: .anyrouter)
        text.capabilities = ["decision"]
        var photoApp = app([yesNo()])
        #expect(DecisionAppsLogic.showsImageInput(app: photoApp, model: see))
        #expect(DecisionAppsLogic.showsImageInput(app: photoApp, model: nil))
        #expect(!DecisionAppsLogic.showsImageInput(app: photoApp, model: text))
        #expect(DecisionAppsLogic.showsImageInput(app: nil, model: see))
        photoApp.acceptsImages = false
        #expect(!DecisionAppsLogic.showsImageInput(app: photoApp, model: see))
    }

    /// Every app names two different models, so one that is gone or cannot read a photo still leaves another to try.
    @Test func everyAppHasAPreferredAndADifferentFallbackModel() throws {
        for app in try apps() {
            #expect(!app.preferredModel.isEmpty && !app.fallbackModel.isEmpty && app.preferredModel != app.fallbackModel, "\(app.id)")
        }
    }

    @Test func theTilesAreTheAppsThenTheCustomDecision() throws {
        let tiles = DecisionAppsLogic.tiles(for: try apps())
        #expect(tiles.count == 8 && tiles.last?.target == .custom && tiles.last?.title == "Custom decision")
        #expect(tiles.first == AppTile(id: "email-triage", title: "Email triage", subtitle: "Paste an email",
                                       symbol: "envelope.badge", target: .decision("email-triage")))
        #expect(Set(tiles.map(\.id)).count == 8)
        #expect(DecisionAppsLogic.tiles(for: []).map(\.target) == [.custom])
    }

    @Test func everyCustomSampleCanRunAndTheScoreDefaultHasTenLevels() {
        #expect(DecisionsLogic.samples.map(\.id) == ["email", "policy", "incident", "invoice"])
        for sample in DecisionsLogic.samples {
            #expect(DecisionsLogic.request(model: "m", state: sample.state, questions: sample.questions) != nil, "\(sample.id)")
        }
        #expect(DecisionsLogic.items(DecisionsLogic.defaultLevels).count == 10)
    }

    @Test func photoProblemsReadAsPlainSentences() {
        #expect(DecisionsLogic.imageProblemText(.unreadable) == "That photo could not be read.")
        #expect(DecisionsLogic.imageProblemText(.tooLarge) == "That photo is too large.")
        #expect(DecisionsLogic.imageProblemText(.tooMany) == "You can add up to 4 photos.")
    }

    // MARK: Result text

    @Test func theResultLineFillsEachToken() throws {
        let triage = try #require(try apps().first)
        let line = DecisionAppsLogic.resultLine(triage, result: result([
            answer("reply", verdict("Yes")),
            answer("urgency", verdict("3", score: 3, max: 4, note: "today")),
            answer("category", verdict("action")),
        ]))
        #expect(line == "It needs a reply. Urgency: today. Category: action.")
        let no = DecisionAppsLogic.resultLine(triage, result: result([answer("reply", verdict("No"))]))
        #expect(no == "It does not need a reply. Urgency: unclear. Category: unclear.")
    }

    @Test func answersReadAsWordsWhateverTheirShape() {
        #expect(DecisionAppsLogic.text(of: verdict("Yes")) == "Yes")
        #expect(DecisionAppsLogic.text(of: verdict("No"), no: "Nope") == "Nope")
        #expect(DecisionAppsLogic.text(of: verdict("Yes"), yes: "Sure") == "Sure")
        #expect(DecisionAppsLogic.text(of: verdict("Yes"), no: "Nope") == "Yes")
        #expect(DecisionAppsLogic.text(of: verdict("No"), yes: "Sure") == "No")
        #expect(DecisionAppsLogic.text(of: verdict("7", score: 7, max: 9)) == "7 of 9")
        #expect(DecisionAppsLogic.text(of: verdict("7", score: 7)) == "7 of 0")
        #expect(DecisionAppsLogic.text(of: .refused("no")) == "declined")
        #expect(DecisionAppsLogic.text(of: .unreadable) == "unclear")
    }

    @Test func theTopBarNamesTheAnswerSoTheCardDoesNotRepeatIt() {
        let options: [DecisionAnswer.Option] = (1...6).map { .init(label: "o\($0)", probability: Double($0) / 10) }
        let picked = DecisionAnswer.Verdict(headline: "O6", options: options)
        #expect(DecisionAppsLogic.bars(of: picked).map(\.label) == ["o6", "o5", "o4", "o3", "o2"])
        #expect(DecisionAppsLogic.answerLine(of: picked) == nil)
        let scored = DecisionAnswer.Verdict(headline: "7", score: 7, maxScore: 9, options: [])
        #expect(DecisionAppsLogic.answerLine(of: scored) == "7 of 9")
        let other = DecisionAnswer.Verdict(headline: "maybe", options: [.init(label: "yes", probability: 0.6)])
        #expect(DecisionAppsLogic.answerLine(of: other) == "maybe")
    }

    @Test func aDeclinedRunSaysSoInsteadOfFillingTokens() {
        let declined = result([answer("a", .refused("policy"))], refusal: "Not allowed")
        #expect(DecisionAppsLogic.resultLine(app([yesNo()]), result: declined) == "The model declined: Not allowed")
        #expect(DecisionAppsLogic.summary(of: declined) == "The model declined: Not allowed")
    }

    @Test func aCustomSummaryListsEachQuestionWithItsAnswer() {
        let done = result([answer("q1", verdict("Yes")), answer("q2", verdict("billing"))])
        #expect(DecisionAppsLogic.summary(of: done) == "Question q1? Yes. Question q2? billing.")
    }
}
