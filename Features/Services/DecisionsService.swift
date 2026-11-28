import Foundation

/// What the Decisions screen needs from AnyRouter. The adapter wraps the AnyRouter engine.
protocol DecisionsService: Sendable {
    func decisionModels() async throws -> [ModelDescriptor]
    func run(_ request: DecisionRequest) async throws -> DecisionResult
}

struct AnyRouterDecisionsAdapter: DecisionsService {
    let engine: AnyRouterEngine

    func decisionModels() async throws -> [ModelDescriptor] { try await engine.decisionModels() }
    func run(_ request: DecisionRequest) async throws -> DecisionResult { try await engine.runDecision(request) }
}
