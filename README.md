# AnyRouter for iPhone and iPad

A native SwiftUI chat app that talks to Apple Foundation Models, local Hugging Face models (GGUF and MLX), and AnyRouter cloud models after you sign in.

Status: early. See [PLAN.md](./PLAN.md).

## Build

Requires Xcode 26 and iOS 26.

```bash
brew install xcodegen
xcodegen generate
open AnyRouter.xcodeproj
```

Personal settings (Team ID) go in `Config/Local.xcconfig`, copied from `Config/Local.xcconfig.example`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [AGENTS.md](./AGENTS.md).

## License

Apache-2.0. See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
