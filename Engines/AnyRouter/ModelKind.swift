import Foundation

/// What a catalog entry is for. The chat picker only ever shows `.chat`.
enum ModelKind: String, Codable, Sendable, CaseIterable {
    case chat, embedding, rerank, decision

    /// Decision models look like text models (`category: "text"`), so they are told apart first,
    /// by the `systemone` capability or the `questions` parameter. Embedding and rerank follow the
    /// category or the output type. Everything else is a chat model.
    static func classify(
        category: String?,
        outputModalities: [String],
        capabilities: [String],
        supportedParameters: [String]
    ) -> ModelKind {
        if capabilities.contains("systemone") || supportedParameters.contains("questions") { return .decision }
        if category == "embedding" || outputModalities.contains("embeddings") { return .embedding }
        if category == "rerank" || outputModalities.contains("scores") { return .rerank }
        return .chat
    }
}
