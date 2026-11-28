import Foundation
import NaturalLanguage

/// Sentence vectors made on the device (agent design 2.2, unit M7), so recall can find an item by meaning without any
/// text leaving the phone and without a consent prompt. Apple's contextual embedding for Latin script covers English and
/// Vietnamese; the English sentence embedding is the fallback while its assets are missing.
@MainActor
final class OnDeviceEmbedder {
    static let shared = OnDeviceEmbedder()

    private let contextual = NLContextualEmbedding(script: .latin)
    private var loaded = false

    /// Fetches the contextual model's assets if the system has them to give. True when some embedding can be made.
    func prepare() async -> Bool {
        if let contextual, !contextual.hasAvailableAssets {
            _ = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
                contextual.requestAssets { result, _ in done.resume(returning: result == .available) }
            }
        }
        return embed("test") != nil
    }

    /// The text's vector and the name of the model that made it; vectors of different models are never compared.
    func embed(_ text: String) -> (vector: [Float], model: String)? {
        if let contextual, contextual.hasAvailableAssets, load(contextual),
           let result = try? contextual.embeddingResult(for: text, language: nil) {
            var tokens: [[Double]] = []
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                tokens.append(vector)
                return true
            }
            if let vector = MemoryEmbeddingLogic.meanPool(tokens) { return (vector, contextual.modelIdentifier) }
        }
        guard let vector = NLEmbedding.sentenceEmbedding(for: .english)?.vector(for: text) else { return nil }
        return (vector.map(Float.init), "nl-sentence-en")
    }

    private func load(_ embedding: NLContextualEmbedding) -> Bool {
        if !loaded { loaded = (try? embedding.load()) != nil }
        return loaded
    }
}
