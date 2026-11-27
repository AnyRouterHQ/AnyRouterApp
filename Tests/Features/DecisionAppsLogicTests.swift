import Foundation
import Testing
@testable import AnyRouter

struct DecisionAppsLogicTests {
    private func apps() throws -> [DecisionApp] { try DecisionAppsLogic.load() }

    private func app(_ questions: [DecisionApp.Question], line: String = "{a}") -> DecisionApp {
        DecisionApp(id: "t", title: "T", symbol: "star", inputHint: "h", acceptsImages: true, defaultModel: nil,
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

    @Test func theBundledCatalogHasTheSixStarterAppsInOrder() throws {
        #expect(try apps().map(\.id) == ["scam-check", "email-triage", "receipt-sort", "incident-triage", "policy-check", "tone-check"])
        #expect(try Set(apps().map(\.id)).count == 6)
        #expect(try apps().allSatisfy { !$0.samples.isEmpty })
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

    @Test func photosShowForPhotoAppsAndModelsNotKnownToBeTextOnly() {
        let see = DecisionModel(id: "a", name: "A", acceptsImages: true)
        let text = DecisionModel(id: "b", name: "B", acceptsImages: false)
        let unknown = DecisionModel(id: "c", name: "C")
        var photoApp = app([yesNo()])
        #expect(DecisionAppsLogic.showsImageInput(app: photoApp, model: see))
        #expect(DecisionAppsLogic.showsImageInput(app: photoApp, model: unknown))
        #expect(DecisionAppsLogic.showsImageInput(app: photoApp, model: nil))
        #expect(!DecisionAppsLogic.showsImageInput(app: photoApp, model: text))
        #expect(DecisionAppsLogic.showsImageInput(app: nil, model: see))
        photoApp.acceptsImages = false
        #expect(!DecisionAppsLogic.showsImageInput(app: photoApp, model: see))
    }

    @Test func anAppStartsOnItsOwnModelWhenListed() {
        let models = [DecisionModel(id: "anyrouter/decision", name: "D"), DecisionModel(id: "x/see", name: "S")]
        var withModel = app([yesNo()])
        withModel.defaultModel = "x/see"
        #expect(DecisionAppsLogic.startingModelID(app: withModel, models: models, current: "anyrouter/decision") == "x/see")
        withModel.defaultModel = "x/gone"
        #expect(DecisionAppsLogic.startingModelID(app: withModel, models: models, current: "x/see") == "x/see")
        #expect(DecisionAppsLogic.startingModelID(app: nil, models: models, current: "gone") == "anyrouter/decision")
    }

    // MARK: Result text

    @Test func theResultLineFillsEachToken() throws {
        let scam = try #require(try apps().first)
        let line = DecisionAppsLogic.resultLine(scam, result: result([
            answer("scam", verdict("Yes")),
            answer("kind", verdict("phishing")),
            answer("risk", verdict("3", score: 3, max: 4, note: "high")),
        ]))
        #expect(line == "This looks like a scam. Closest type: phishing. Risk: high.")
        let no = DecisionAppsLogic.resultLine(scam, result: result([answer("scam", verdict("No"))]))
        #expect(no == "This does not look like a scam. Closest type: unclear. Risk: unclear.")
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
