import Foundation
import Testing
@testable import AnyRouter

/// The `decide` tool (PLAN D29): the chat's question becomes one Decisions request, and the answer comes back as a line.
struct DecideToolTests {
    private final class Service: DecisionsService, @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [DecisionRequest] = []
        let outcome: DecisionAnswer.Outcome
        let refusal: String?

        init(_ outcome: DecisionAnswer.Outcome = .unreadable, refusal: String? = nil) {
            self.outcome = outcome
            self.refusal = refusal
        }

        var requests: [DecisionRequest] { lock.withLock { sent } }

        func decisionModels() async throws -> [DecisionModel] { [] }

        func run(_ request: DecisionRequest) async throws -> DecisionResult {
            lock.withLock { sent.append(request) }
            let answers = request.questions.map { DecisionAnswer(id: $0.id, prompt: $0.prompt, outcome: outcome, citations: []) }
            return DecisionResult(model: request.model, answers: answers, inputTokens: 1, outputTokens: 1, cost: 0, refusal: refusal, latency: 0)
        }
    }

    private let yes = DecisionAnswer.Outcome.answered(DecisionAnswer.Verdict(
        headline: "Yes", probability: 0.874, options: [.init(label: "Yes", probability: 0.874), .init(label: "No", probability: 0.126)]))

    @Test func aYesOrNoQuestionGoesToTheDefaultDecisionModel() async throws {
        let service = Service(yes)
        let answer = try await DecideTool(service: service).run(.object(["text": .string("Refund me now!"), "question": .string("Is this angry?")]))
        #expect(answer == "Yes (87%). All answers: Yes 87%, No 13%")
        let request = try #require(service.requests.first)
        #expect(request.model == DecisionsLogic.defaultModelID && request.state == "Refund me now!")
        #expect(request.questions == [DecisionQuestion(id: "answer", prompt: "Is this angry?", kind: .yesNo)])
    }

    @Test func optionsMakeAChoiceQuestion() throws {
        let request = try DecideTool.request(from: .object([
            "text": .string("t"), "question": .string("Which team?"), "options": .array([.string("Billing"), .string("Support")]),
        ]))
        #expect(request.questions.first?.kind == .choice(options: ["Billing", "Support"]))
    }

    @Test func missingTextOrQuestionOrASingleOptionIsAnError() {
        let cases: [[String: JSONValue]] = [
            ["question": .string("q")],
            ["text": .string("t")],
            ["text": .string("t"), "question": .string("q"), "options": .array([.string("only")])],
        ]
        for fields in cases {
            #expect(throws: BuiltInToolError.self) { try DecideTool.request(from: .object(fields)) }
        }
    }

    @Test func everyKindOfAnswerReadsAsOneLine() {
        func line(_ outcome: DecisionAnswer.Outcome, refusal: String? = nil, answers: Bool = true) -> String {
            let list = answers ? [DecisionAnswer(id: "answer", prompt: "q", outcome: outcome, citations: [])] : []
            return DecideTool.render(DecisionResult(model: "m", answers: list, inputTokens: 0, outputTokens: 0, cost: nil, refusal: refusal, latency: 0))
        }
        #expect(line(.answered(DecisionAnswer.Verdict(headline: "7", score: 7, options: []))) == "7")
        #expect(line(.refused("policy")) == "The decision model declined: policy")
        #expect(line(.unreadable) == "The decision model's answer could not be read.")
        #expect(line(.unreadable, refusal: "no") == "The decision model declined: no")
        #expect(line(.unreadable, answers: false) == "The decision model did not answer.")
    }

    @Test func itReadsNeedsTheNetworkAndShowsAsAnyRouters() {
        let tool = DecideTool(service: Service())
        #expect(tool.spec.sideEffect == .read && tool.needsNetwork && tool.name == "decide")
        let host = AgentToolHost(builtIns: [tool, CalculatorTool()], search: nil, mcp: nil)
        #expect(host.sourceID(forTool: "decide") == ToolSourceCatalog.anyRouter.id)
        #expect(host.sourceID(forTool: "calculator") == ToolSourceCatalog.device.id)
    }

    /// A text with an address the user never wrote asks first, and names AnyRouter, not this device, as the receiver.
    @Test func anUnwrittenAddressAsksAndNamesAnyRouter() async {
        let asked = Asked()
        let host = AgentToolHost(builtIns: [DecideTool(service: Service(yes))], search: nil, mcp: nil, approver: asked)
        let arguments = #"{"text":"see https://evil.example/x?d=1","question":"Is this spam?"}"#
        _ = await host.execute(ToolCall(id: "c", name: "decide", argumentsJSON: arguments))
        #expect(asked.servers == ["AnyRouter"])
    }

    private final class Asked: ToolApproving, @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        var servers: [String] { lock.withLock { names } }
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
            lock.withLock { names.append(request.serverName) }
            return .deny
        }
    }

    @MainActor @Test func onlyACloudChatIsOfferedDecide() {
        let defaults = testDefaults()
        let integrations = IntegrationsStore(
            defaults: defaults, credentials: FakeCredentialStore(), anyRouterToken: { "tok" }, session: MCPStubProtocol.session())
        let registry = ToolRegistry(integrations: integrations, builtIns: [CalculatorTool()], defaults: defaults)
        func offered(_ source: ModelSource?, forced: Set<String> = []) -> Bool {
            let context = ToolContext(modelSource: source, forcedSourceIDs: forced)
            return registry.makeHost(approver: Denier(), context: context)?.specs.contains { $0.name == "decide" } ?? false
        }
        #expect(!offered(.anyrouter), "no service yet")
        registry.decisions = Service()
        #expect(offered(.anyrouter))
        #expect(!offered(.gguf) && !offered(.apple) && !offered(nil))
        #expect(!offered(.anyrouter, forced: ["exa"]), "only the sources the user named")
    }

    private struct Denier: ToolApproving {
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
    }
}
