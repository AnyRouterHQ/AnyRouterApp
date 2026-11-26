# Sidebar

The thread list: pinned and recent chats, system search, a settings button and a new-chat button.

## Sub-features

- `sidebar-open` opens from `Menu` on iPhone.
- `sidebar-search` the `sidebar.search` button opens a full-screen search (`search.close` dismisses it) with the keyboard up; typing filters.
- `sidebar-select` picking a thread closes the drawer and shows that chat.
- `sidebar-new-chat` starts a blank chat.
- `sidebar-swipe` swipe or long-press offers Delete, Pin and Rename (not automated).

## How to get to it (user POV)

- Choose `Menu` in the chat toolbar (iPhone) or use the always-open column (iPad).

## Driving it with the journeys harness

Preconditions:

- Demo launch.

- **Open.** Tap `Menu`. The search field `Search chats` appears; `Explain Swift actors` and the pinned `Trip ideas for Lisbon` are listed.
- **Search.** Tap `sidebar.search`. A full-screen search opens with the keyboard already up; type `swift`. `Trip ideas for Lisbon` leaves the list, `Explain Swift actors` stays.
- **Select.** Tap the `Explain Swift actors` result. The search and drawer close and the static text `Key points:` is visible.
- **New chat.** Tap `New chat`. `home.greeting` is shown.
- **Proof.** Screenshots `drawer-open`, `search-open`, `search-filtered`, `thread-opened`, `new-chat-home`. Journey: `drawer`.

## Gotchas

- Two buttons are named `New chat` while the drawer is open (sidebar bottom bar and chat toolbar); the journey taps it after the drawer closed.
- On iPad the toggle is the system sidebar button, not `Menu`.
- Rename, pin and delete use swipe actions and context menus and are not covered yet.
