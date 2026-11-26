import Foundation
import Jinja

/// A GGUF model's own chat template, rendered with the Jinja engine the MLX path already uses.
/// llama.cpp's C API only knows a fixed list of templates; a newer model's template is jinja-only, and ChatML would be
/// the wrong format for it.
struct JinjaChatTemplate: @unchecked Sendable {
    private let template: Template

    /// Nil when the template does not compile (syntax this engine does not support).
    init?(source: String) {
        guard let compiled = try? Template(source) else { return nil }
        template = compiled
    }

    /// The prompt text for the conversation, ending where the model's reply starts. Nil when the template fails on it
    /// (for example it calls `raise_exception`) or renders nothing.
    func render(_ messages: [PromptMessage], bos: String?, eos: String?) -> String? {
        do {
            let list = try messages.map { try Value(any: ["role": $0.role, "content": $0.content] as [String: Any]) }
            let context: [String: Value] = [
                "messages": .array(list),
                "add_generation_prompt": .boolean(true),
                // Models that can think start without it: the app shows no thinking yet.
                "enable_thinking": .boolean(false),
                "bos_token": .string(bos ?? ""),
                "eos_token": .string(eos ?? ""),
            ]
            let text = try template.render(context)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
