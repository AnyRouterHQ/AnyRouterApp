# Model catalog

The list of local models in the app comes from JSON files in this repo. Adding or changing a model is a commit to
`catalog/`, not an app release.

| File | Used by |
|---|---|
| `catalog/models.json` | Production. Bundled in the app as the offline fallback, and fetched from GitHub at launch and on pull-to-refresh. |
| `catalog/dev-models.json` | Development. Fetched when **Settings > Catalog source > Use the development catalog** is on. Try new entries here first. |

Remote URL: `https://raw.githubusercontent.com/AnyRouterHQ/AnyRouterApp/main/catalog/models.json` (and `dev-models.json`).
A user can replace it with their own https URL in Settings.

## How the app uses it

1. Shows the bundled list at once.
2. Fetches the remote file with `If-None-Match` (ETag). `304` means nothing changed.
3. Accepts a remote file only if it decodes and its `schemaVersion` is one the app understands. Otherwise it keeps the cached copy, then the bundled one. A bad file never empties the hub.
4. Merges by entry id: user-added models over remote over bundled. A remote file that leaves out a bundled model does not remove it.

## Add a model

```bash
# GGUF: one file of a repo
scripts/catalog-add.sh <hf-repo> <file.gguf> --catalog catalog/dev-models.json \
    --title "Name" --summary "One sentence." --params 4B --icon gemma

# MLX: the whole snapshot
scripts/catalog-add.sh <hf-repo> --mlx --catalog catalog/dev-models.json --title "Name (MLX)" --summary "..."
```

The script fills size, `sha256` (the LFS oid), the pinned commit `revision`, context length, license, quantization and dates from the
Hugging Face API. Then edit by hand what it cannot know: `summary`, `badges`, `vision`, `platforms`, `isOnboarding`, `recommended`.
`--update` refreshes an existing entry (new revision, size, sha256) and keeps your hand-written fields.

The same script fills `memory` (KV-cache bytes per token, sliding-window layers, expert share) from the model's own GGUF header or MLX
`config.json`. The app uses it to say whether the model runs on the device and which context it can load with. `scripts/catalog-memory.sh`
refreshes it for every entry.

Check before you push:

```bash
scripts/catalog-check.sh              # both files, against Hugging Face
scripts/catalog-check.sh --offline    # schema only
```

CI runs the same check on every change to `catalog/**` (Ubuntu, no macOS minutes).

Only models the app can run belong in `models.json`. The llama.cpp build in `Packages/LlamaBinary` decides which GGUF architectures load.
Test a new entry in `dev-models.json` or with the `model-smoke` workflow before it goes to production.

## Fields

| Field | Meaning |
|---|---|
| `repo`, `format` (`gguf` or `mlx`), `file` | What to download. `file` is for GGUF only. The entry id is `gguf/<repo>/<file>` or `mlx/<repo>`. |
| `revision` | Full 40-character commit sha. Never a branch. |
| `sizeBytes` | The file, or the sum of the MLX snapshot files. |
| `sha256` | GGUF only. The app refuses a download whose listing disagrees. |
| `title`, `summary`, `parameters`, `quantization`, `contextLength`, `license` | Display. |
| `capabilities` | `chat`, `reasoning`, ... |
| `iconKey` | Short key for the card icon, for example `qwen`, `gemma`, `llama`. |
| `badges` | `[{"label": "New", "tone": "success"}]`. Tones: `info`, `success`, `warning`, `neutral`. |
| `supportsThinking` | The model has a thinking mode. |
| `vision` | `{"mmprojFile": "...", "mmprojSize": 0}`, the projector in the same repo. Data only until image input ships. |
| `isOnboarding` | Offered first in onboarding when it fits the device. |
| `recommended` | Top pick. |
| `platforms` | `["ios", "ipados"]`. Omit for all. |
| `minRAMBytes` | Do not offer as runnable below this much RAM. |
| `memory` | `{"fullKVBytesPerToken": n, "windowKVBytesPerToken": n, "windowTokens": n, "activeFraction": 0.119}`. Written by the scripts. Without it the app estimates from the file size. |
| `createdAt`, `updatedAt` | `yyyy-MM-dd`. |
| `order` | Smaller first. |

The envelope is `{"schemaVersion": 1, "updatedAt": "yyyy-MM-dd", "models": [...]}`. A breaking change to the schema raises `schemaVersion`;
older apps then ignore the remote file and keep their bundled list.
