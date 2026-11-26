// swift-tools-version: 6.0
import PackageDescription

// The official llama.cpp Apple build, pinned by tag and checksum.
// b10456 is the newest release that still ships iOS Simulator and device slices; from b10488 on the
// xcframework has device slices only, which CI (Simulator) cannot link. Move the pin when upstream restores them.
let package = Package(
    name: "LlamaBinary",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10456/llama-b10456-xcframework.zip",
            checksum: "0223bedd0a01232399d943dcb72bc227882bc90df98e29d7a92343531a88cc02"
        ),
    ]
)
