import Foundation
import Testing
@testable import AnyRouter

/// The scripted half of the memory eval (agent design 5.2, 5.3, unit L1): 30 memories, 10 questions in English and
/// Vietnamese, each with the items it should recall. Recall at 3 decides M7: embeddings only if it stays under 0.9.
/// Measured with a port of the scorer before this test existed: 0.77, then 0.85 with plural folding and "our" as a stop
/// word. Two of the misses need meaning, not words ("dinner" for "vegetarian", "rains" for "rainy"), and in the app
/// "I am vegetarian" is an About you item that every prompt carries anyway.
struct MemoryRecallEvalTests {
    struct Prompt {
        let question: String
        let want: [Int]
        init(_ question: String, want: [Int]) {
            self.question = question
            self.want = want
        }
    }

    static let memories = [
        "My dog is called Mochi",
        "Mochi is allergic to chicken",
        "I am vegetarian",
        "My sister Lan lives in Hue",
        "I work night shifts at the hospital",
        "My car is a blue Honda City",
        "I take the bus to work on rainy days",
        "My daughter starts school in September",
        "I am learning Japanese, level N4",
        "My favourite coffee is cà phê sữa đá",
        "Tôi bị dị ứng hải sản",
        "Mẹ tôi sống ở Đà Lạt",
        "Tôi đang tập chạy bộ mỗi sáng",
        "Con mèo của tôi tên là Mít",
        "My laptop is a 2021 MacBook Air",
        "I prefer trains over planes",
        "My budget for the trip is 10 million dong",
        "I run a small bakery in District 3",
        "Our wedding anniversary is on 14 March",
        "I play badminton on Saturdays",
        "My password manager is 1Password",
        "I have a peanut allergy",
        "My son plays piano",
        "I moved to Saigon in 2019",
        "My boss is called Minh",
        "I drink green tea in the afternoon",
        "Our team uses Swift and Kotlin",
        "I want to save for a house",
        "My grandmother turns 90 next year",
        "I usually cook dinner at 7 pm",
    ]

    static let prompts = [
        Prompt("What treats can I give Mochi?", want: [0, 1]),
        Prompt("Suggest a dinner recipe for tonight", want: [2]),
        Prompt("What should I bring when I visit my sister in Hue?", want: [3]),
        Prompt("Gợi ý món ăn cho tôi, nhớ là tôi dị ứng", want: [10]),
        Prompt("Plan a weekend trip to Đà Lạt to see my mother", want: [11]),
        Prompt("How do I get to the hospital for my night shift if it rains?", want: [4, 6]),
        Prompt("Help me study Japanese grammar", want: [8]),
        Prompt("Train or plane to Hanoi for my trip budget?", want: [15, 16]),
        Prompt("Gift ideas for our wedding anniversary", want: [18]),
        Prompt("Ideas for my bakery's new menu", want: [17]),
    ]

    static let candidates = memories.enumerated().map {
        MemoryRecallLogic.Candidate(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0.offset))!, text: $0.element)
    }

    /// Recall at 3 and wrong recalls, with a semantic score per question (none for BM25 alone).
    static func measure(semantic: (String) -> [UUID: Double]) -> (found: Int, wanted: Int, wrong: Int) {
        var found = 0
        var wanted = 0
        var wrong = 0
        for prompt in prompts {
            let ranked = MemoryRecallLogic.rank(prompt.question, candidates, semantic: semantic(prompt.question))
            let top = ranked.prefix(3).compactMap { hit in candidates.firstIndex { $0.id == hit.candidate.id } }
            found += prompt.want.filter { top.contains($0) }.count
            wanted += prompt.want.count
            wrong += top.filter { !prompt.want.contains($0) }.count
        }
        return (found, wanted, wrong)
    }

    /// The CI log shows test events but not what a test prints, so the numbers go out as a known issue: the run stays
    /// green and the line is searchable ("memory eval").
    static func report(_ line: String) {
        withKnownIssue("Measurement report, not a failure") { Issue.record(Comment(rawValue: line)) }
    }

    @Test func recallAtThreeAndWrongRecallsOnTheFixture() {
        let lexical = Self.measure { _ in [:] }
        let recall = Double(lexical.found) / Double(lexical.wanted)
        Self.report("memory eval (BM25): recall at 3 \(lexical.found)/\(lexical.wanted) = \(recall), wrong recalls \(lexical.wrong)")
        #expect(recall >= 0.8, "recall at 3 fell: \(lexical.found)/\(lexical.wanted)")
        #expect(lexical.wrong <= 4, "wrong recalls rose: \(lexical.wrong)")
    }

    /// Unit M7: the same fixture with Apple's on-device embeddings added to BM25. Skipped, with a line in the log, where the
    /// Simulator has no embedding assets; the BM25 floor above still holds there.
    @MainActor @Test func hybridRecallWithOnDeviceEmbeddings() async {
        let embedder = OnDeviceEmbedder()
        guard await embedder.prepare() else {
            Self.report("memory eval (hybrid): skipped, no NaturalLanguage embedding on this Simulator")
            return
        }
        let vectors = Self.candidates.compactMap { candidate in embedder.embed(candidate.text).map { (candidate.id, $0) } }
        let hybrid = Self.measure { question in
            guard let query = embedder.embed(question) else { return [:] }
            var similarities: [UUID: Double] = [:]
            for (id, item) in vectors where item.model == query.model {
                similarities[id] = MemoryEmbeddingLogic.cosine(query.vector, item.vector)
            }
            return MemoryEmbeddingLogic.standout(similarities)
        }
        let lexical = Self.measure { _ in [:] }
        Self.report("memory eval (hybrid, \(vectors.first?.1.model ?? "none")): recall at 3 \(hybrid.found)/\(hybrid.wanted), wrong \(hybrid.wrong); BM25 \(lexical.found)/\(lexical.wanted), wrong \(lexical.wrong)")
        #expect(hybrid.found >= lexical.found, "meaning must not lose what words found")
    }
}
