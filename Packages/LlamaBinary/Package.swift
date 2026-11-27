// swift-tools-version: 6.0
import PackageDescription

// llama.cpp built by .github/workflows/llama-xcframework.yml from the pinned tag, with iOS device and Simulator slices.
// Upstream releases ship device slices only since b10488, and CI runs on the Simulator.
// To move the pin: run that workflow with the new tag, then paste its URL and checksum here.
// b12811: inkling2_loop needs b12611 or later (ggml-org/llama.cpp#32704); older builds load the files but give garbage.
// It also covers Gemma 4, Qwen 3.5, LFM2 and SmolLM3. llama.h changed only in the quantize parameters since b12603.
let package = Package(
    name: "LlamaBinary",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/AnyRouterHQ/AnyRouterApp/releases/download/llama-b12811/llama-b12811-xcframework.zip",
            checksum: "524bef3031591e0314a9885f90bae2ee52ae25488f0b59cce45aa90af98e53a4"
        ),
    ]
)
