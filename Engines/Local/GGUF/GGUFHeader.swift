import Foundation

/// What the fit check needs from a GGUF header: layer count, trained context and the memory profile pieces.
struct GGUFInfo: Equatable, Sendable {
    var architecture: String
    var blockCount: Int
    var trainedContext: Int
    /// Nil when the architecture's metadata does not carry the attention keys (the app then estimates).
    var memory: CatalogMemory?

    func profile(fileBytes: Int64) -> ModelMemoryProfile {
        guard let memory else { return .estimated(fileBytes: fileBytes, trainedContext: trainedContext) }
        return ModelMemoryProfile(
            fileBytes: fileBytes, fullKVBytesPerToken: memory.fullKVBytesPerToken,
            windowKVBytesPerToken: memory.windowKVBytesPerToken ?? 0, windowTokens: memory.windowTokens ?? 0,
            trainedContext: trainedContext, activeFraction: memory.activeFraction)
    }
}

enum GGUFHeaderError: Error, Equatable {
    /// The bytes ended before the metadata did. Read more and try again.
    case needMoreData
    case notGGUF
    case unsupported(String)
}

/// Reads the metadata block of a GGUF file: just enough keys to size the KV cache. Token tables are skipped, not decoded.
enum GGUFHeader {
    /// How much of the file to read, in turn, until the metadata is complete. Vocabularies make headers tens of MB.
    static let readSizes = [4, 16, 64, 192].map { $0 * 1024 * 1024 }

    enum Value: Equatable, Sendable {
        case int(Int64)
        case double(Double)
        case bool(Bool)
        case string(String)
        case ints([Int64])
        case bools([Bool])
        case other

        var int: Int? {
            switch self {
            case .int(let v): Int(v)
            case .bool(let v): v ? 1 : 0
            default: nil
            }
        }
    }

    /// Parses the header at the start of `data`. Throws `.needMoreData` when `data` ends inside the metadata.
    static func parse(_ data: Data) throws -> GGUFInfo {
        var reader = Cursor(data: data)
        guard try reader.bytes(4) == Data("GGUF".utf8) else { throw GGUFHeaderError.notGGUF }
        _ = try reader.u32()
        _ = try reader.u64() // tensor count
        let count = try reader.u64()
        var meta: [String: Value] = [:]
        for _ in 0..<count {
            let key = try reader.string()
            let kind = try reader.u32()
            meta[key] = try reader.value(kind: kind, keep: wanted(key))
        }
        return try info(from: meta)
    }

    /// The first bytes of a local file, enough for the metadata.
    static func read(fileAt url: URL) throws -> GGUFInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        for size in readSizes {
            try handle.seek(toOffset: 0)
            let data = try handle.read(upToCount: size) ?? Data()
            do {
                return try parse(data)
            } catch GGUFHeaderError.needMoreData where data.count == size {
                continue
            }
        }
        throw GGUFHeaderError.unsupported("The GGUF header is larger than \(readSizes.last! / 1_048_576) MB.")
    }

    // MARK: Keys

    private static let suffixes = [
        "block_count", "context_length", "embedding_length", "attention.head_count", "attention.head_count_kv",
        "attention.key_length", "attention.value_length", "attention.key_length_swa", "attention.value_length_swa",
        "attention.sliding_window", "attention.sliding_window_pattern", "attention.shared_kv_layers",
        "expert_count", "expert_used_count",
    ]

    private static func wanted(_ key: String) -> Bool {
        key == "general.architecture" || suffixes.contains { key.hasSuffix("." + $0) }
    }

    /// Same rules as `scripts/catalog.py` (memory_from_gguf), so a catalog entry and a downloaded file agree.
    static func info(from meta: [String: Value]) throws -> GGUFInfo {
        guard case .string(let architecture)? = meta["general.architecture"] else {
            throw GGUFHeaderError.unsupported("The file has no architecture.")
        }
        let p = architecture + "."
        let layers = meta[p + "block_count"]?.int ?? 0
        let trained = meta[p + "context_length"]?.int ?? 0
        guard layers > 0, let embedding = meta[p + "embedding_length"]?.int,
              let heads = perLayer(meta[p + "attention.head_count"], count: layers)
        else {
            return GGUFInfo(architecture: architecture, blockCount: layers, trainedContext: trained, memory: nil)
        }
        let kvHeads = perLayer(meta[p + "attention.head_count_kv"], count: layers) ?? heads
        let keyLength = meta[p + "attention.key_length"]?.int
        let valueLength = meta[p + "attention.value_length"]?.int
        let keyWindow = meta[p + "attention.key_length_swa"]?.int ?? keyLength
        let valueWindow = meta[p + "attention.value_length_swa"]?.int ?? valueLength
        let window = meta[p + "attention.sliding_window"]?.int ?? 0
        let shared = meta[p + "attention.shared_kv_layers"]?.int ?? 0

        var period: Int?
        var flags: [Bool]?
        switch meta[p + "attention.sliding_window_pattern"] {
        case .bools(let list)?: flags = list
        case .int(let n)?: period = Int(n)
        default: break
        }
        // llama.cpp's built-in default for Gemma 3: five window layers, then one full layer.
        if flags == nil, period == nil, window > 0, architecture == "gemma3" || architecture == "gemma3n" { period = 6 }

        func isWindow(_ layer: Int) -> Bool {
            guard window > 0 else { return false }
            if let flags { return layer < flags.count && flags[layer] }
            if let period, period > 1 { return layer % period < period - 1 }
            return false
        }

        var full: Int64 = 0
        var windowed: Int64 = 0
        for layer in 0..<max(0, layers - shared) {
            let kv = kvHeads[layer]
            if kv == 0 { continue } // a layer without attention keeps no KV cache
            let swa = isWindow(layer)
            let keyDim = (swa ? keyWindow : keyLength) ?? embedding / max(1, heads[layer])
            let valueDim = (swa ? valueWindow : valueLength) ?? embedding / max(1, heads[layer])
            let bytes = Int64(kv * (keyDim + valueDim) * 2)
            if swa { windowed += bytes } else { full += bytes }
        }
        let experts = meta[p + "expert_count"]?.int ?? 0
        let used = meta[p + "expert_used_count"]?.int ?? 0
        let memory = CatalogMemory(
            fullKVBytesPerToken: full,
            windowKVBytesPerToken: windowed > 0 ? windowed : nil,
            windowTokens: windowed > 0 ? window : nil,
            activeFraction: ModelMemoryProfile.activeFraction(expertCount: experts, expertsUsed: used))
        return GGUFInfo(architecture: architecture, blockCount: layers, trainedContext: trained, memory: memory)
    }

    /// A key that is one number for every layer, or one number per layer.
    private static func perLayer(_ value: Value?, count: Int) -> [Int]? {
        switch value {
        case .int(let v)?: Array(repeating: Int(v), count: count)
        case .ints(let list)? where list.count >= count: list.prefix(count).map { Int($0) }
        default: nil
        }
    }

    // MARK: Binary cursor

    private struct Cursor {
        let data: Data
        var position: Int

        init(data: Data) {
            self.data = data
            self.position = data.startIndex
        }

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, position + count <= data.endIndex else { throw GGUFHeaderError.needMoreData }
            defer { position += count }
            return data.subdata(in: position..<position + count)
        }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, position + count <= data.endIndex else { throw GGUFHeaderError.needMoreData }
            position += count
        }

        mutating func u8() throws -> UInt8 { try bytes(1)[0] }
        mutating func u32() throws -> UInt32 { try bytes(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) } }
        mutating func u64() throws -> UInt64 { try bytes(8).withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) } }

        mutating func string() throws -> String {
            let length = try u64()
            guard length < 1 << 28 else { throw GGUFHeaderError.unsupported("A GGUF string is implausibly long.") }
            return String(decoding: try bytes(Int(length)), as: UTF8.self)
        }

        /// Size in bytes of a fixed-size value type, nil for strings and arrays.
        static func width(of kind: UInt32) -> Int? {
            switch kind {
            case 0, 1, 7: 1
            case 2, 3: 2
            case 4, 5, 6: 4
            case 10, 11, 12: 8
            default: nil
            }
        }

        mutating func scalar(kind: UInt32) throws -> Value {
            switch kind {
            case 0: return .int(Int64(try u8()))
            case 1: return .int(Int64(Int8(bitPattern: try u8())))
            case 2: return .int(Int64(UInt16(littleEndian: try bytes(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })))
            case 3: return .int(Int64(Int16(littleEndian: try bytes(2).withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })))
            case 4: return .int(Int64(try u32()))
            case 5: return .int(Int64(Int32(bitPattern: try u32())))
            case 6: return .double(Double(Float(bitPattern: try u32())))
            case 7: return .bool(try u8() != 0)
            case 10: return .int(Int64(truncatingIfNeeded: try u64()))
            case 11: return .int(Int64(bitPattern: try u64()))
            case 12: return .double(Double(bitPattern: try u64()))
            default: throw GGUFHeaderError.unsupported("Unknown GGUF value type \(kind).")
            }
        }

        /// Reads one value. Values nobody asked for (`keep` false) are skipped without decoding.
        mutating func value(kind: UInt32, keep: Bool) throws -> Value {
            if kind == 8 {
                let text = try string()
                return keep ? .string(text) : .other
            }
            if kind == 9 {
                let inner = try u32()
                let count = Int(try u64())
                if let width = Self.width(of: inner) {
                    if !keep || count > 4096 {
                        try skip(count * width)
                        return .other
                    }
                    var ints: [Int64] = []
                    var bools: [Bool] = []
                    for _ in 0..<count {
                        let item = try scalar(kind: inner)
                        if case .bool(let b) = item { bools.append(b) } else if case .int(let i) = item { ints.append(i) }
                    }
                    return inner == 7 ? .bools(bools) : .ints(ints)
                }
                for _ in 0..<count { _ = try value(kind: inner, keep: false) }
                return .other
            }
            return try scalar(kind: kind)
        }
    }
}
