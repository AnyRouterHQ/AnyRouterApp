# Sidebar

The thread list: the app name and logo, a Search chats row, pinned and recent chats with View all, a More section (Decisions), and a bottom bar with a round Settings (gear) button and New chat.

## Sub-features

- `sidebar-open` opens from `Menu` on iPhone.
- `sidebar-search` the `sidebar.search` button opens a full-screen search (`search.close` dismisses it) with the keyboard up; typing filters.
- `sidebar-viewall` the `sidebar.viewall` button on Recents opens the same search with every chat listed.
- `sidebar-decisions` the Decisions row under More opens the Decisions sheet.
- `sidebar-select` picking a thread closes the drawer and shows that chat.
- `sidebar-new-chat` starts a blank chat.
- `sidebar-swipe` swipe or long-press offers Delete, Pin and Rename (not automated).

## How to get to it (user POV)

- Choose `Menu` in the chat toolbar (iPhone) or use the always-open column (iPad).

## Driving it with the journeys harness

Preconditions:

- Demo launch.

- **Open.** Tap `Menu`. The `Search chats` row appears (there is no inline search field); `Explain Swift actors` and the pinned `Trip ideas for Lisbon` are listed.
- **Search.** Tap `sidebar.search`. A full-screen search opens with the keyboard already up; type `swift`. `Trip ideas for Lisbon` leaves the list, `Explain Swift actors` stays.
- **Select.** Tap the `Explain Swift actors` result. The search and drawer close and the static text `Key points:` is visible.
- **New chat.** Tap `New chat`. `home.greeting` is shown.
- **Proof.** Screenshots `drawer-open`, `search-open`, `search-filtered`, `thread-opened`, `new-chat-home`. Journey: `drawer`.

## Gotchas

- Two buttons are named `New chat` while the drawer is open (sidebar bottom bar and chat toolbar); the journey taps it after the drawer closed.
- The chat beside the open drawer is not dimmed. A clear `Close sidebar` button covers it and closes the drawer on tap.
- On iPad the toggle is the system sidebar button, not `Menu`.
- Rename, pin and delete use swipe actions and context menus and are not covered yet.
