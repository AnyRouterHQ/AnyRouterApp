import Foundation
@testable import AnyRouter

enum VoiceFixtures {
    static func model(
        _ id: String, kind: VoiceModelKind = .stt, languages: [String] = ["*"], detects: Bool = false, weak: [String] = [],
        size: Int64 = 100_000_000, order: Int? = nil
    ) -> VoiceModel {
        VoiceModel(
            id: id, kind: kind, engine: kind == .stt ? .whisperKit : .moonshine, title: id, languages: languages,
            detectsLanguage: detects, weakLanguages: weak, license: "MIT", sourceURL: URL(string: "https://example.com/\(id)")!,
            order: order, sizeBytes: size)
    }

    static func catalogJSON(version: Int = 1, id: String = "whisper-test", path: String = "a/b.bin", url: String = "https://example.com/b.bin") -> Data {
        Data("""
        {"version": \(version), "models": [{"id": "\(id)", "kind": "stt", "engine": "whisperKit", "title": "T",
        "languages": ["*"], "license": "MIT", "sourceURL": "https://example.com", "sizeBytes": 10,
        "files": [{"path": "\(path)", "url": "\(url)", "sizeBytes": 10}]}]}
        """.utf8)
    }
}
