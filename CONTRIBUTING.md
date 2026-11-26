# Contributing

Thanks for helping. The rules for contributors and agents live in [AGENTS.md](./AGENTS.md); scope and status live in [PLAN.md](./PLAN.md).

- Build with Xcode 26: `brew install xcodegen && xcodegen generate`, then open `AnyRouter.xcodeproj`.
- Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for personal settings. Never commit it.
- Commits: `type(scope): subject`. One PR per coherent change. CI must be green.
- Never commit secrets, Team IDs, device identifiers, or personal paths.
