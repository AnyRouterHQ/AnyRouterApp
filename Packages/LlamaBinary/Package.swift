// swift-tools-version: 6.0
import PackageDescription

// llama.cpp built by .github/workflows/llama-xcframework.yml from the pinned tag, with iOS device and Simulator slices.
// Upstream releases ship device slices only since b10488, and CI runs on the Simulator.
// To move the pin: run that workflow with the new tag, then paste its URL and checksum here.
// b12603 is the first tag that runs the 26B looped-core models (inkling2_loop) and also covers Gemma 4, Qwen 3.5, LFM2 and SmolLM3.
let package = Package(
    name: "LlamaBinary",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/AnyRouterHQ/AnyRouterApp/releases/download/llama-b12603/llama-b12603-xcframework.zip",
            checksum: "8cd9e88eeaeb211e73499dde1737361d3f32e86a575f0c8bae7a252fbdc61544"
        ),
    ]
)
