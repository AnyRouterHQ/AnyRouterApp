import Foundation

/// The math of hybrid recall (agent design 2.2, unit M7): sentence vectors from token vectors, cosine similarity, and
/// which items stand out from the rest by meaning. Lexical BM25 stays; meaning only adds items words cannot find.
enum MemoryEmbeddingLogic {
    /// How far above the other items, in standard deviations, an item's similarity must be to count by meaning alone.
    /// Measured with the relevance floor on (CI 46119393019, English sentence model on the Simulator): 1.5 gave 11/13 with
    /// 12 wrong; 3.0 with one item at most gives 10/13 with 0 wrong and no L1 trap, against BM25's 9/13.
    static let standoutThreshold = 3.0
    /// Fewer items than this give no spread to stand out from.
    static let minimumForStandout = 3

    /// The mean of token vectors: one vector for a sentence. Nil without tokens.
    static func meanPool(_ vectors: [[Double]]) -> [Float]? {
        guard let width = vectors.first?.count, width > 0 else { return nil }
        var sum = [Double](repeating: 0, count: width)
        for vector in vectors where vector.count == width {
            for index in 0..<width { sum[index] += vector[index] }
        }
        return sum.map { Float($0 / Double(vectors.count)) }
    }

    /// 0 for vectors of different sizes or with no length.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for index in a.indices {
            dot += Double(a[index]) * Double(b[index])
            normA += Double(a[index]) * Double(a[index])
            normB += Double(b[index]) * Double(b[index])
        }
        return normA > 0 && normB > 0 ? dot / (normA.squareRoot() * normB.squareRoot()) : 0
    }

    /// Each item's similarity in standard deviations above the mean of all of them. Empty when there are too few items
    /// or no spread.
    static func standout(_ similarities: [UUID: Double]) -> [UUID: Double] {
        guard similarities.count >= minimumForStandout else { return [:] }
        let values = Array(similarities.values)
        let mean = values.reduce(0, +) / Double(values.count)
        let spread = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
        guard spread > 0 else { return [:] }
        return similarities.mapValues { ($0 - mean) / spread }
    }

    /// At most one item counts by meaning alone: the one that stands out most, and only past the threshold.
    static func strongest(_ standout: [UUID: Double]) -> [UUID: Double] {
        guard let best = standout.max(by: { $0.value < $1.value }), best.value >= standoutThreshold else { return [:] }
        return [best.key: best.value]
    }

    static func data(_ vector: [Float]) -> Data { vector.withUnsafeBufferPointer { Data(buffer: $0) } }

    static func vector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
