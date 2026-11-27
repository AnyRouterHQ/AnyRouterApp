import Foundation

/// Runs a title request on the engine the plan names.
enum TitleGenerator {
    /// The cleaned title, or nil when the engine failed, was cancelled, or answered with nothing usable.
    @MainActor
    static func title(for plan: TitlePlan, registry: EngineRegistry) async -> String? {
        var params = GenerationParams()
        params.temperature = 0.2
        params.maxTokens = TitleLogic.maxTokens
        params.systemPrompt = plan.system
        var text = ""
        do {
            for try await delta in registry.engine(for: plan.model).stream(model: plan.model, messages: plan.messages, params: params, tools: nil) {
                if Task.isCancelled { return nil }
                if case .text(let piece) = delta { text += piece }
            }
        } catch {
            return nil
        }
        return Task.isCancelled ? nil : TitleLogic.clean(text)
    }
}
