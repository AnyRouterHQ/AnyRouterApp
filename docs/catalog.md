# Model catalog

The list of local models in the app comes from JSON files in this repo. Adding or changing a model is a commit to
`catalog/`, not an app release.

| File | Used by |
|---|---|
| `catalog/models.json` | Production. Bundled in the app as the offline fallback, and fetched from GitHub at launch and on pull-to-refresh. |
| `catalog/dev-models.json` | Development. Fetched when **Settings > Local Models > Catalog Sources > AnyRouter catalog > Use the development catalog** is on. Try new models here first. |

Remote URL: `https://raw.githubusercontent.com/AnyRouterHQ/AnyRouterApp/main/catalog/models.json` (and `dev-models.json`).
A user can replace it with their own https URL in Settings.

## Shape

`{"schemaVersion": 2, "updatedAt": "yyyy-MM-dd", "families": [family]}`. A family is a model line at one generation, with its
sizes. The app lists families first, then the sizes of one family.

| Family field | Meaning |
|---|---|
| `id`, `name`, `publisher` | `gemma-4`, "Gemma 4", "Google". |
| `line` | The model line across generations (`gemma`). At most one **current** family per line. |
| `logo` | Short key for the logo (`gemma`, `qwen`, `llama`, `liquid`). Unknown keys get a generic mark. |
| `summary`, `website` | One line, and an https link. The summary makes no memory claims. |
| `tags` | `thinking`, `vision`, `audio`, `tools`, `code`, `multilingual`, `mobile`. Only what the app can use today. `mobile` means a size runs well on a 6 GB phone; a test checks it against the fit check. |
| `badges` | `best`, `recommended`, `new`, `experimental`. `experimental` shows "Experimental · slow", keeps the family out of the top picks, and lists a size that runs here after them in Featured. |
| `status`, `replacedBy` | `current` or `deprecated`. A deprecated family names the current family that replaces it. |
| `order` | Smaller first. |
| `variants` | The sizes. |

| Variant field | Meaning |
|---|---|
| `repo`, `engine` (`gguf` or `mlx`), `file` | What to download. `file` is for GGUF only. The app's id for it is `gguf/<repo>/<file>` or `mlx/<repo>`. |
| `params`, `quant` | "4B", "E2B"; "Q4_K_M", "4-bit". |
| `revision` | Full 40-character commit sha. Never a branch. |
| `sizeBytes` | The file, or the sum of the MLX snapshot files. |
| `sha256` | GGUF only. The app refuses a download whose listing disagrees. |
| `contextLength`, `license` | Display and fit. |
| `memory` | `{"fullKVBytesPerToken", "windowKVBytesPerToken", "windowTokens", "activeFraction", "lazyWeightBytes"}`. Written by the scripts from the model's own metadata: KV cache per token, sliding-window layers, expert share, and the embedding tables that mmap keeps out of RAM. The app's fit check uses it. |
| `vision` | `{"mmprojFile", "mmprojSize", "imageSide"}`: the projector file in the same repo, its size, and the longest image side to feed it. The app downloads it with the model and the size accepts photos (llama.cpp `mtmd`). The family needs the `vision` tag. Add it with `--mmproj FILE --image-side 896`. |
| `isOnboarding` | Offered first in onboarding when it fits the device. |
| `sampling` | GGUF only, optional: `{"temperature", "topP", "topK", "minP", "maxOutputTokens"}`. The publisher's sampling, used for this size in place of the app's settings, and a cap on one reply, thinking included. `topK` 0 and `minP` 0 turn those filters off. |
| `platforms`, `minRAMBytes` | `["ios", "ipados"]`; omit for all. |
| `createdAt`, `updatedAt` | `yyyy-MM-dd`. "Newest" sorts by them. |

## Add a size

```bash
# GGUF: one file of a repo, into an existing family
scripts/catalog-add.sh <hf-repo> <file.gguf> --catalog catalog/dev-models.json --family gemma-4 --params E2B

# MLX: the whole snapshot
scripts/catalog-add.sh <hf-repo> --mlx --catalog catalog/dev-models.json --family gemma-4 --params E2B

# A new family: say who makes it
scripts/catalog-add.sh <hf-repo> <file.gguf> --family smollm-3 --params 3B --name SmolLM3 --publisher "Hugging Face" \
    --line smollm --logo smollm --summary "One line." --website https://huggingface.co/HuggingFaceTB --tags thinking
```

The script fills size, `sha256` (the LFS oid), the pinned commit `revision`, context length, license, quantization, dates and
`memory` from the Hugging Face API and the file's header. `--update` refreshes a size (new revision, size, sha256) and keeps
what you wrote by hand. `scripts/catalog-memory.sh` refreshes `memory` for every size.

Check before you push:

```bash
scripts/catalog-check.sh              # both files, against Hugging Face
scripts/catalog-check.sh --offline    # schema only
```

CI runs the same check on every change to `catalog/**` (Ubuntu, no macOS minutes). It fails when a family has an unknown
tag or badge, a current family shares its `line` with another current family, a current size lacks a pinned revision, size,
sha256 or memory facts, a deprecated family lacks `replacedBy`, a summary talks about RAM or GB, or a file on Hugging Face no
longer matches.

## Curation

1. Keep the list short: at most three sizes per family, the best quant per size, GGUF and MLX only where both are tested.
2. One current generation per line. When a new generation lands, set the old family to `deprecated` with `replacedBy`; do not delete it.
3. A deprecated model is hidden from browsing, search and recommendations. A person who installed it keeps using it, sees "Older model, try <replacement>" in Local Models, and can delete it.
4. A model enters `models.json` only after it loaded and answered in the `model-smoke` workflow. New ones start in `dev-models.json`.
5. Memory claims come from the `memory` facts and the fit check, never from prose.

## Streamed models

A mixture-of-experts file too big for the app's memory limit can still run from mmap: only the experts a token uses stay
resident, the rest is read from storage through the page cache. `FitPlanner` calls this `.streamed`. It needs a device
whose RAM holds the whole file plus about 4 GB for iOS and other apps (`FitPlanner.streamingSystemBytes`), so a 6.9 GB
file needs a 12 GB iPhone; below that, Local Models > Not Available says "Needs an iPhone with 12 GB of memory." A streamed
model loads with a 4,096-token context, mmap on, no mlock, and every layer on the CPU (Metal would map the whole file into
GPU buffers that count against the app). Replies are slow: give the size a `sampling.maxOutputTokens` cap.

## Photos

A GGUF size with a `vision` entry takes photos on the device. llama.cpp's `mtmd` reads the `mmproj` projector next to the
model file; the app loads it the first time a photo is sent, not with the model. A size shows the `vision` badge only when
the projector is on disk and `FitPlanner.imageInput` says the device has room for weights, projector and image encoder
together. A model installed before its projector shipped has to be downloaded again. Photos are shrunk to `imageSide` before
they are encoded, at most four per message; photos of earlier turns stay as the text read from them. The smoke test
`testNamesTheColorOfAPhoto` sends a solid red photo and expects "red".

The llama.cpp build in `Packages/LlamaBinary` decides which GGUF architectures load. A breaking change to the schema raises
`schemaVersion`; older apps then ignore the remote file and keep their bundled list.
