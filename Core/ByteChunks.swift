import Foundation

extension AsyncSequence where Element == UInt8 {
    /// Hands the bytes to `body` in chunks of at most `size`, cutting early after each `delimiter` so a line-based
    /// stream is not held back waiting for the buffer to fill. `body` returns `false` to stop reading.
    func forEachChunk(size: Int = 16 * 1024, endingAt delimiter: UInt8? = nil, _ body: (Data) async throws -> Bool) async throws {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(size)
        for try await byte in self {
            buffer.append(byte)
            guard buffer.count >= size || byte == delimiter else { continue }
            let chunk = Data(buffer)
            buffer.removeAll(keepingCapacity: true)
            let more = try await body(chunk)
            if !more { return }
        }
        if !buffer.isEmpty { _ = try await body(Data(buffer)) }
    }
}
