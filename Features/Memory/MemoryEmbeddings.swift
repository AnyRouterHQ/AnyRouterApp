import Foundation

extension MemoryStore {
    /// Most item vectors one recall makes; the rest are made by later recalls, so a send never waits on hundreds.
    static let vectorsPerRecall = 40

    /// How far each item stands out from the others by meaning for `question` (MemoryEmbeddingLogic.standout). Item
    /// vectors are kept on the item with the model that made them and made again when the model changes.
    /// Empty without an embedder or a vector for the question.
    func semanticScores(for question: String, among records: [MemoryRecord], embedder: OnDeviceEmbedder?) -> [UUID: Double] {
        guard let embedder, let query = embedder.embed(question) else { return [:] }
        var made = 0
        var similarities: [UUID: Double] = [:]
        for record in records {
            if record.embeddingModel != query.model || record.embedding == nil {
                guard made < Self.vectorsPerRecall, let item = embedder.embed(record.text), item.model == query.model else { continue }
                record.embedding = MemoryEmbeddingLogic.data(item.vector)
                record.embeddingModel = item.model
                made += 1
            }
            if let data = record.embedding {
                similarities[record.id] = MemoryEmbeddingLogic.cosine(query.vector, MemoryEmbeddingLogic.vector(data))
            }
        }
        return MemoryEmbeddingLogic.standout(similarities)
    }
}
