# Hub (Manage models)

The list of local models: installed ones with Delete, ones downloading with progress and Pause or Cancel, ones not installed with Download, a fit badge, and search.

## Sub-features

- `hub-installed` shows Apple Intelligence and the installed GGUF models.
- `hub-progress` shows the 42% download.
- `hub-search` filters the list.
- `hub-sort-filter` the Sort and Filter menus open.
- `hub-fit` fit badges per card (screenshot judgment only).
- `hub-hf-search` Hugging Face repo search (needs the network, not driven).

## How to get to it (user POV)

- Settings, then `Manage models`.

## Driving it with the journeys harness

Preconditions:

- Demo launch. Catalog: Qwen3 0.6B and Llama 3.2 1B installed, Gemma 3 1B downloading at 42%, Qwen3 1.7B and Llama 3.2 3B not installed (3B shows a tight fit).

- **Open.** Settings, tap `Manage models`. Element `hub.list` exists and a row labeled with `Qwen3 0.6B` is present; `hub.storage` shows storage use.
- **Progress.** Scroll until a row labeled with `42%` exists.
- **Sort and filter.** Tap `hub.sort` and `hub.filter`; each opens a menu (screenshots).
- **Search.** Tap the search field `Search models`, type `Llama`. The `Qwen3 0.6B` row disappears; `Llama 3.2 1B` stays.
- **Proof.** Screenshots `hub-top`, `hub-download-progress`, `hub-sort-menu`, `hub-filter-menu`, `hub-search-llama`. Judge fit badges in the screenshots. Journey: `hub`.

## Gotchas

- Rows are combined accessibility elements; match them by label (`CONTAINS`), not by static text.
- Download, Pause and Cancel are no-ops in demo data. Do not claim a real download was verified.
- Real downloads and device-fit numbers are covered by the model-smoke workflow, not here.
