import Foundation
import Testing
@testable import AnyRouter

/// `decide` spends AnyRouter credits: the cost shows on its row and counts in the reply; outside a cloud chat it asks
/// every time with the notice of "Ask a cloud model" (manager decision on D28).
struct DecideCostTests {
    private final class Service: DecisionsService, @unchecked Sendable {
        func decisionModels() async throws -> [DecisionModel] { [] }
        func run(_ request: DecisionRequest) async throws -> DecisionResult {
            DecisionResult(model: request.model, answers: [], inputTokens: 10, outputTokens: 1, cost: 0.0004, refusal: nil, latency: 0.1)
        }
    }

    private final class Approver: ToolApproving, @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [ToolApprovalRequest] = []
        var requests: [ToolApprovalRequest] { lock.withLock { seen } }
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
            lock.withLock { seen.append(request) }
            return .allowOnce
        }
    }

    private let call = ToolCall(id: "c", name: "decide", argumentsJSON: #"{"text":"Great product","question":"Is it positive?"}"#)

    @Test func inACloudChatItRunsWithoutAskingAndCarriesItsCost() async {
        let approver = Approver()
        let host = AgentToolHost(builtIns: [DecideTool(service: Service())], search: nil, mcp: nil, approver: approver)
        let result = await host.execute(call)
        #expect(!result.isError && result.costUSD == Decimal(0.0004))
        #expect(approver.requests.isEmpty)
    }

    @Test func inADeviceChatItAsksEveryTimeAndNamesAnyRouterAndTheCredits() async {
        let approver = Approver()
        let tool = DecideTool(service: Service(), onDevice: true)
        #expect(tool.sideEffect == .external && DecideTool(service: Service()).approvalNote == nil)
        let host = AgentToolHost(builtIns: [tool], search: nil, mcp: nil, approver: approver)
        _ = await host.execute(call)
        _ = await host.execute(call)
        #expect(approver.requests.count == 2, "asked every time")
        #expect(approver.requests.first?.serverName == "AnyRouter")
        #expect(approver.requests.first?.reason?.contains("credits") == true && approver.requests.first?.canRemember == false)
    }

    @Test func theRowShowsTheCostAndTheReplyCountsIt() {
        var result = ToolResult(callID: "c", name: "decide", text: "Yes (90%)", isError: false)
        result.costUSD = Decimal(0.0004)
        let step = ToolStep(call: call, result: result)
        #expect(ToolRowLogic.title(for: step).hasSuffix(" \u{00B7} " + PriceFormat.cost(Decimal(0.0004))))
        #expect(!ToolRowLogic.title(for: ToolStep(call: call, result: ToolResult(callID: "c", name: "decide", text: "", isError: false))).contains("$"))
        let cloud = ModelDescriptor(id: "anyrouter/auto", source: .anyrouter, displayName: "Auto", contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        let device = ModelDescriptor(id: "apple/foundation", source: .apple, displayName: "Apple", contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        let cloudReply = ChatViewModel.finalMetadata(nil, tokens: nil, model: cloud, ttftMs: nil, totalMs: 1, toolCostUSD: Decimal(0.0004), nameOf: { _ in nil })
        #expect(cloudReply.costUSD == Decimal(0.0004))
        let deviceReply = ChatViewModel.finalMetadata(nil, tokens: nil, model: device, ttftMs: nil, totalMs: 1, toolCostUSD: Decimal(0.0004), nameOf: { _ in nil })
        #expect(deviceReply.costUSD == Decimal(0.0004), "credits spent from a device chat count too")
    }
}
