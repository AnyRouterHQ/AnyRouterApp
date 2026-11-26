# Integrations

Settings page listing MCP servers and their tools, with a per-tool toggle, connection status, and an Add server sheet.

## Sub-features

- `integrations-list` servers and connection status.
- `integrations-tool-toggle` enabling or disabling a tool, persisted.
- `integrations-add` add a custom server by URL and token.

## How to get to it (user POV)

- Settings, then `Integrations`.

## Driving it with the journeys harness

Preconditions:

- Not automated. Demo data has no MCP servers, and the store talks to the network.

- **Needed to automate.** A fake integrations store in `DemoData` with one connected server and three tools, then a journey that flips a tool toggle and proves the effect after a relaunch (`-ARDemoKeepSettings YES`).
- **Status.** Report as not covered.

## Gotchas

- Toggling a tool needs a connected server; signed-out shows "Sign in with AnyRouter in Settings to use these tools".
- The tool toggle id does not exist yet; add `.accessibilityIdentifier("integration-tool-<name>")` in `toolRow` with the journey.
