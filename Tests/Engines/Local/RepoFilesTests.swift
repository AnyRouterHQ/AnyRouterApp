import Foundation
import Testing
@testable import AnyRouter

struct RepoFilesTests {
    @Test(arguments: [
        ("Qwen3-4B-Q4_K_M.gguf", "Q4_K_M"),
        ("Llama-3.2-1B-Instruct-Q8_0.gguf", "Q8_0"),
        ("model-IQ4_XS.gguf", "IQ4_XS"),
        ("gemma-3-1b-it-q4_0.gguf", "Q4_0"),
        ("model-bf16.gguf", "BF16"),
        ("model-F16.gguf", "F16"),
    ])
    func readsTheQuantizationFromTheFileName(name: String, expected: String) {
        #expect(RepoFiles.quantization(inFileName: name) == expected)
    }

    @Test func fileNamesWithoutAQuantizationGiveNil() {
        #expect(RepoFiles.quantization(inFileName: "Qwen3-4B.gguf") == nil)
    }

    private let listing: [HFFile] = [
        HFFile(path: "README.md", size: 10),
        HFFile(path: "m-Q8_0.gguf", size: 8_000),
        HFFile(path: "m-Q4_K_M.gguf", size: 4_000),
        HFFile(path: "m-Q2_K.gguf", size: 2_000),
        HFFile(path: "mmproj-m-F16.gguf", size: 900),
        HFFile(path: "big-Q4_K_M-00001-of-00003.gguf", size: 50_000),
    ]

    @Test func ggufChoicesDropProjectorsAndShardsAndSortBySize() {
        let choices = RepoFiles.ggufChoices(listing)
        #expect(choices.map(\.path) == ["m-Q2_K.gguf", "m-Q4_K_M.gguf", "m-Q8_0.gguf"])
        #expect(choices.map(\.quantization) == ["Q2_K", "Q4_K_M", "Q8_0"])
    }

    @Test func defaultChoicePrefersQ4KMWhenItFits() {
        let choices = RepoFiles.ggufChoices(listing)
        let roomy = DeviceFit(physicalMemory: 64 * 1024 * 1024 * 1024)
        #expect(RepoFiles.defaultChoice(choices, fit: roomy)?.quantization == "Q4_K_M")
    }

    @Test func defaultChoiceFallsBackToTheSmallestFileWhenNothingFits() {
        let choices = [
            GGUFChoice(path: "a-Q4_K_M.gguf", sizeBytes: 9_000_000_000, quantization: "Q4_K_M"),
            GGUFChoice(path: "b-Q2_K.gguf", sizeBytes: 5_000_000_000, quantization: "Q2_K"),
        ]
        let small = DeviceFit(physicalMemory: 4 * 1024 * 1024 * 1024)
        #expect(RepoFiles.defaultChoice(choices, fit: small)?.path == "b-Q2_K.gguf")
    }

    @Test func defaultChoiceOfNothingIsNil() {
        #expect(RepoFiles.defaultChoice([]) == nil)
    }

    @Test func mlxSnapshotKeepsWeightsConfigAndTokenizerOnly() {
        let files = [
            ".gitattributes", "README.md", "config.json", "model.safetensors", "model.safetensors.index.json",
            "tokenizer.json", "tokenizer.model", "merges.txt", "chat_template.jinja", "notes.pdf", "sub/.hidden.json",
        ].map { HFFile(path: $0, size: 1) }
        let kept = RepoFiles.mlxSnapshotFiles(files).map(\.path)
        #expect(kept == [
            "config.json", "model.safetensors", "model.safetensors.index.json",
            "tokenizer.json", "tokenizer.model", "merges.txt", "chat_template.jinja",
        ])
    }

    @Test func entriesForAGGUFRepoGiveOneEntryPerFile() throws {
        let entries = try RepoFiles.entries(repo: "org/Name-GGUF", format: .gguf, files: listing, revision: "abc")
        #expect(entries.map(\.id) == [
            "gguf/org/Name-GGUF/m-Q2_K.gguf", "gguf/org/Name-GGUF/m-Q4_K_M.gguf", "gguf/org/Name-GGUF/m-Q8_0.gguf",
        ])
        #expect(entries.allSatisfy { $0.origin == .user && $0.revision == "abc" && $0.title == "Name-GGUF" })
    }

    @Test func entriesForAnMLXRepoSumTheSnapshotSize() throws {
        let files = [
            HFFile(path: "README.md", size: 5), HFFile(path: "config.json", size: 100),
            HFFile(path: "model.safetensors", size: 900),
        ]
        let entries = try RepoFiles.entries(repo: "org/m-4bit", format: .mlx, files: files)
        #expect(entries.count == 1)
        #expect(entries.first?.sizeBytes == 1_000)
        #expect(entries.first?.id == "mlx/org/m-4bit")
    }

    @Test func reposWithoutUsableFilesAreReportedNotSilentlyEmpty() {
        #expect(throws: LocalModelError.noFiles("org/m")) {
            try RepoFiles.entries(repo: "org/m", format: .gguf, files: [HFFile(path: "README.md", size: 1)])
        }
        #expect(throws: LocalModelError.noFiles("org/m")) {
            try RepoFiles.entries(repo: "org/m", format: .mlx, files: [HFFile(path: "config.json", size: 1)])
        }
        #expect(throws: LocalModelError.invalidRepo("nope")) {
            try RepoFiles.entries(repo: "nope", format: .mlx, files: [])
        }
    }

    @Test func downloadPlanPicksTheEntrysGGUFFileWithItsChecksum() throws {
        let files = [HFFile(path: "a.gguf", size: 1, sha256: "x"), HFFile(path: "b.gguf", size: 2, sha256: "y")]
        let plan = try RepoFiles.downloadPlan(for: sampleGGUF(file: "b.gguf"), files: files)
        #expect(plan == [HFFile(path: "b.gguf", size: 2, sha256: "y")])
        #expect(throws: LocalModelError.notFound("c.gguf")) {
            try RepoFiles.downloadPlan(for: sampleGGUF(file: "c.gguf"), files: files)
        }
    }

    @Test func downloadPlanForMLXNeedsWeights() throws {
        let files = [HFFile(path: "config.json", size: 1), HFFile(path: "model.safetensors", size: 2)]
        #expect(try RepoFiles.downloadPlan(for: sampleMLX(), files: files).count == 2)
        #expect(throws: LocalModelError.noFiles("org/model-4bit")) {
            try RepoFiles.downloadPlan(for: sampleMLX(), files: [HFFile(path: "config.json", size: 1)])
        }
    }
}

struct DeviceFitTests {
    private let gib: UInt64 = 1024 * 1024 * 1024

    @Test func smallModelsFitAnEightGigabytePhone() {
        let fit = DeviceFit(physicalMemory: 8 * gib)
        #expect(fit.verdict(modelBytes: 396_705_472) == .fits)
        #expect(fit.verdict(modelBytes: 1_107_409_472) == .fits)
        #expect(fit.verdict(modelBytes: 2_019_377_696) == .fits)
    }

    @Test func aFourBillionParameterModelIsTightOnEightGigabytes() {
        #expect(DeviceFit(physicalMemory: 8 * gib).verdict(modelBytes: 2_497_281_312) == .tight)
    }

    @Test func modelsAboveHalfOfRAMAreTooLarge() {
        #expect(DeviceFit(physicalMemory: 8 * gib).verdict(modelBytes: 6_000_000_000) == .tooLarge)
        #expect(DeviceFit(physicalMemory: 4 * gib).verdict(modelBytes: 2_497_281_312) == .tooLarge)
    }

    @Test func workingSetAddsOverheadToTheWeights() {
        let fit = DeviceFit(physicalMemory: 8 * gib)
        #expect(fit.workingSetBytes(modelBytes: 1_000_000_000) == 1_000_000_000 + 200_000_000 + 512 * 1024 * 1024)
    }

    @Test func unknownMemoryNeverClaimsAFit() {
        #expect(DeviceFit(physicalMemory: 0).verdict(modelBytes: 1) == .tooLarge)
    }

    @Test func negativeSizesAreTreatedAsZero() {
        #expect(DeviceFit(physicalMemory: 8 * gib).verdict(modelBytes: -5) == .fits)
    }
}
