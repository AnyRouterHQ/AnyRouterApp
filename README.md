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
- Threads with search, markdown rendering, stop and regenerate, and a model picker.
- Photo, camera and PDF attachments, with vision for cloud models and for local models that have a projector.
- Reasoning shown as a "Thought for Ns" row, and tool calls shown as rows you can open.
- Tools for every model source: clock, calculator, web search, page reader, and your AnyRouter MCP tools. Writes and outside calls ask first.
- Memory, skills and sub-agents for research, with Settings pages to review and delete.
- Voice: dictation, spoken replies, and optional Whisper and Qwen3-TTS downloads.

**Apps**
- Decisions, Paste and Extract as native screens, plus Shortcuts, Control Center controls and a Share extension.

**Downloads**
- Background downloads that resume, with checksum verification.

**Layout**
- Made for both iPhone and iPad.

## Get the app

TestFlight. Setup and install steps are in [docs/testflight.md](./docs/testflight.md). Unsigned debug build for Sideloadly or AltStore: [docs/sideload.md](./docs/sideload.md).

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
- Syntax highlighting in code blocks
- Photos for MLX models
- Calendar, reminders and contacts tools
- Speculative decoding and KV cache options for local models
- Image generation

## Contributing

See [AGENTS.md](./AGENTS.md) and [CONTRIBUTING.md](./CONTRIBUTING.md).

## Credits

Built with [llama.cpp](https://github.com/ggml-org/llama.cpp), [MLX](https://github.com/ml-explore/mlx-swift) and [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui). See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

## License

Apache-2.0.
