<p align="center">
  <img src="docs/assets/logo.png" alt="AnyRouter logo" width="120">
</p>

<h1 align="center">AnyRouter</h1>

<p align="center">A private chat app for iPhone and iPad. On-device and cloud models in one place.</p>

<p align="center">
  <a href="https://github.com/AnyRouterHQ/AnyRouterApp/actions/workflows/ci.yml"><img src="https://github.com/AnyRouterHQ/AnyRouterApp/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%2026%2B-lightgrey" alt="Platform: iOS and iPadOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
</p>

AnyRouter is a native SwiftUI chat app. You can chat with models that run on your device, or with cloud models through your AnyRouter account, and switch between them from one model picker.

## Features

**Models**
- Apple Foundation Models, on device.
- Local Hugging Face models in GGUF (llama.cpp) and MLX.
- A configurable catalog: a bundled list, your own Hugging Face repos, a remote catalog URL, and Hugging Face search. Each model shows whether it fits your device.
- AnyRouter cloud models.

**Account**
- Sign in with AnyRouter. The key is stored in the Keychain only.

**Chat**
- Threads, markdown rendering, stop and regenerate, and a model picker.

**Downloads**
- Background downloads that resume, with checksum verification.

**Layout**
- Made for both iPhone and iPad.

## Get the app

TestFlight. Setup and install steps are in [docs/testflight.md](./docs/testflight.md).

## Build from source

```bash
# Xcode 26 required
brew install xcodegen
xcodegen generate
open AnyRouter.xcodeproj
```

Put your Team ID in `Config/Local.xcconfig` (copy `Config/Local.xcconfig.example`).

## Privacy

Local models and Apple Foundation Models never leave your device. AnyRouter cloud models send your messages to anyrouter.dev only when you pick one.

## Roadmap

Planned, not built yet:
- Reasoning stream with a collapsible thinking block
- Image attachments (vision models)
- Syntax highlighting in code blocks
- A native Mac version

## Contributing

See [AGENTS.md](./AGENTS.md) and [CONTRIBUTING.md](./CONTRIBUTING.md).

## Credits

The UI is inspired by and ported from [Atomic Chat](https://github.com/AtomicBot-ai/Atomic-Chat) (Apache-2.0). Built with [llama.cpp](https://github.com/ggml-org/llama.cpp), [MLX](https://github.com/ml-explore/mlx-swift) and [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui). See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

## License

Apache-2.0.
