"""Catalog tooling: add a model to catalog/models.json, or check every entry against Hugging Face.

Run through scripts/catalog-add.sh and scripts/catalog-check.sh (python3 -I, standard library only).
All HTTP goes through curl so the system certificate store is used.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

HF = "https://huggingface.co"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILES = ["catalog/models.json", "catalog/dev-models.json"]
SCHEMA_VERSION = 1
MLX_EXTENSIONS = {"safetensors", "json", "model", "txt", "jinja", "tiktoken"}
TONES = {"info", "success", "warning", "neutral"}
PLATFORMS = {"ios", "ipados"}
REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")
QUANT_RE = re.compile(r"(?i)(?<![A-Za-z0-9])((?:IQ|Q)\d(?:_[A-Z0-9]+)*|BF16|F16|F32)(?![A-Za-z0-9])")
KNOWN_KEYS = {
    "repo", "format", "file", "title", "summary", "parameters", "quantization", "sizeBytes", "contextLength",
    "license", "revision", "capabilities", "order", "sha256", "iconKey", "badges", "supportsThinking", "vision",
    "isOnboarding", "platforms", "recommended", "minRAMBytes", "createdAt", "updatedAt",
}

_cache = {}


def fetch_json(url):
    if url not in _cache:
        out = subprocess.run(
            ["curl", "-fsSL", "--retry", "3", "--retry-delay", "2", "-H", "Accept: application/json", url],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            raise RuntimeError(f"GET {url} failed (curl exit {out.returncode}): {out.stderr.strip()}")
        _cache[url] = json.loads(out.stdout)
    return _cache[url]


def tree(repo, revision):
    """Every file of the repo at the revision, as {path: {size, sha256}}."""
    listing = fetch_json(f"{HF}/api/models/{repo}/tree/{revision}?recursive=true")
    return {
        item["path"]: {"size": item["size"], "sha256": (item.get("lfs") or {}).get("oid")}
        for item in listing
        if item.get("type") == "file"
    }


def model_info(repo):
    return fetch_json(f"{HF}/api/models/{repo}")


def entry_id(entry):
    return f"gguf/{entry['repo']}/{entry.get('file', '')}" if entry.get("format") == "gguf" else f"mlx/{entry['repo']}"


def mlx_snapshot_size(files):
    return sum(
        meta["size"]
        for path, meta in files.items()
        if path.rsplit(".", 1)[-1].lower() in MLX_EXTENSIONS and not os.path.basename(path).startswith(".")
    )


def load(path):
    with open(path) as handle:
        return json.load(handle)


def save(path, document):
    with open(path, "w") as handle:
        json.dump(document, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


# ---- add -------------------------------------------------------------------------------------------------------

def cmd_add(args):
    options = {"--catalog": "catalog/models.json", "--title": None, "--summary": None, "--params": None,
               "--icon": None, "--revision": None}
    flags = {"--mlx", "--onboarding", "--recommended", "--thinking", "--update"}
    positional, given = [], set()
    it = iter(args)
    for arg in it:
        if arg in options:
            options[arg] = next(it, None)
        elif arg in flags:
            given.add(arg)
        else:
            positional.append(arg)
    mlx = "--mlx" in given
    if len(positional) != (1 if mlx else 2):
        sys.exit("usage: catalog-add.sh <hf-repo> <file.gguf> [options]\n       catalog-add.sh <hf-repo> --mlx [options]\n"
                 "options: --catalog PATH --title T --summary S --params 4B --icon KEY --revision SHA\n"
                 "         --onboarding --recommended --thinking --update")
    repo = positional[0]
    file = None if mlx else positional[1]
    if not REPO_RE.match(repo) or ".." in repo:
        sys.exit(f"not a Hugging Face repo id: {repo}")

    info = model_info(repo)
    revision = options["--revision"] or info["sha"]
    files = tree(repo, revision)
    entry = {"repo": repo, "format": "mlx" if mlx else "gguf"}
    if mlx:
        if not any(p.endswith(".safetensors") for p in files):
            sys.exit(f"{repo} has no .safetensors files at {revision}")
        size = mlx_snapshot_size(files)
        quant = None
        context = ((info.get("config") or {}).get("text_config") or info.get("config") or {}).get("max_position_embeddings")
    else:
        if file not in files:
            sys.exit(f"{file} is not in {repo} at {revision}. Files: " + ", ".join(sorted(p for p in files if p.endswith(".gguf"))))
        meta = files[file]
        size = meta["size"]
        match = QUANT_RE.search(os.path.basename(file))
        quant = match.group(1).upper() if match else None
        gguf = info.get("gguf") or {}
        context = gguf.get("context_length")
        entry["file"] = file
        if not meta["sha256"]:
            sys.exit(f"{file} has no LFS sha256 at {revision}; refusing to add an unverifiable file")

    license_tag = next((t.split(":", 1)[1] for t in info.get("tags", []) if t.startswith("license:")), None)
    name = repo.split("/")[1]
    entry["title"] = options["--title"] or re.sub(r"[-_]?(GGUF|MLX)$", "", name, flags=re.I).replace("-", " ").replace("_", " ")
    entry["summary"] = options["--summary"] or "TODO: one sentence for the card."
    if options["--params"]:
        entry["parameters"] = options["--params"]
    if quant:
        entry["quantization"] = quant
    entry["sizeBytes"] = size
    if context:
        entry["contextLength"] = context
    if license_tag:
        entry["license"] = license_tag
    entry["revision"] = revision
    if not mlx:
        entry["sha256"] = files[file]["sha256"]
    entry["capabilities"] = ["chat"]
    if options["--icon"]:
        entry["iconKey"] = options["--icon"]
    if "--thinking" in given:
        entry["supportsThinking"] = True
    if "--onboarding" in given:
        entry["isOnboarding"] = True
    if "--recommended" in given:
        entry["recommended"] = True
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    entry["updatedAt"] = today

    path = os.path.join(ROOT, options["--catalog"])
    document = load(path)
    models = document["models"]
    existing = next((i for i, m in enumerate(models) if entry_id(m) == entry_id(entry)), None)
    if existing is not None and "--update" not in given:
        sys.exit(f"{entry_id(entry)} is already in {options['--catalog']}; pass --update to refresh it")
    if existing is not None:
        old = models[existing]
        entry["order"] = old.get("order")
        entry["createdAt"] = old.get("createdAt", today)
        for key in ("summary", "title", "parameters", "iconKey", "badges", "supportsThinking", "vision",
                    "isOnboarding", "platforms", "recommended", "minRAMBytes"):
            if key in old and key not in options_set(options, given):
                entry[key] = old[key]
        models[existing] = ordered(entry)
    else:
        entry["order"] = max([m.get("order", -1) for m in models] + [-1]) + 1
        entry["createdAt"] = today
        models.append(ordered(entry))
    document["updatedAt"] = today
    save(path, document)
    print(f"{'updated' if existing is not None else 'added'} {entry_id(entry)}: {size} bytes, rev {revision[:8]}"
          + ("" if mlx else f", sha256 {entry['sha256'][:12]}"))
    if entry["summary"].startswith("TODO"):
        print("edit the summary (and badges, iconKey, vision) by hand, then run scripts/catalog-check.sh")


def options_set(options, given):
    return {k.lstrip("-") for k, v in options.items() if v is not None} | {k.lstrip("-") for k in given}


ORDER = ["repo", "format", "file", "title", "summary", "parameters", "quantization", "sizeBytes", "contextLength",
         "license", "revision", "sha256", "capabilities", "iconKey", "badges", "supportsThinking", "vision",
         "isOnboarding", "platforms", "recommended", "minRAMBytes", "createdAt", "updatedAt", "order"]


def ordered(entry):
    return {k: entry[k] for k in ORDER if k in entry} | {k: v for k, v in entry.items() if k not in ORDER}


# ---- check -----------------------------------------------------------------------------------------------------

def check_file(path, offline):
    problems = []

    def bad(index, message):
        label = f"{path}[{index}]" if index is not None else path
        problems.append(f"{label}: {message}")

    try:
        document = load(os.path.join(ROOT, path))
    except (OSError, ValueError) as error:
        return [f"{path}: cannot read: {error}"]
    if document.get("schemaVersion") != SCHEMA_VERSION:
        bad(None, f"schemaVersion must be {SCHEMA_VERSION}, got {document.get('schemaVersion')!r}")
    models = document.get("models")
    if not isinstance(models, list) or not models:
        bad(None, "models must be a non-empty list")
        return problems

    seen = {}
    for i, m in enumerate(models):
        unknown = set(m) - KNOWN_KEYS
        if unknown:
            bad(i, f"unknown keys {sorted(unknown)}")
        fmt = m.get("format")
        repo = m.get("repo", "")
        if fmt not in ("gguf", "mlx"):
            bad(i, f"format must be gguf or mlx, got {fmt!r}")
            continue
        if not REPO_RE.match(repo) or ".." in repo:
            bad(i, f"invalid repo {repo!r}")
            continue
        if fmt == "gguf" and not str(m.get("file", "")).endswith(".gguf"):
            bad(i, "a gguf entry needs a file ending in .gguf")
            continue
        ident = entry_id(m)
        if ident in seen:
            bad(i, f"duplicate id {ident} (also entry {seen[ident]})")
        seen[ident] = i
        for key in ("title", "summary"):
            if not str(m.get(key, "")).strip() or str(m.get(key, "")).startswith("TODO"):
                bad(i, f"{ident}: {key} is missing or still a TODO")
        if not isinstance(m.get("sizeBytes"), int) or m["sizeBytes"] <= 0:
            bad(i, f"{ident}: sizeBytes must be a positive integer")
        if not re.fullmatch(r"[0-9a-f]{40}", str(m.get("revision", ""))):
            bad(i, f"{ident}: revision must be a 40-character commit sha, not a branch")
        if fmt == "gguf" and not re.fullmatch(r"[0-9a-f]{64}", str(m.get("sha256", ""))):
            bad(i, f"{ident}: sha256 must be 64 lowercase hex characters")
        if "sha256" in m and fmt == "mlx":
            bad(i, f"{ident}: sha256 applies to a single file; leave it out for MLX")
        for badge in m.get("badges", []):
            if not str(badge.get("label", "")).strip() or badge.get("tone", "neutral") not in TONES:
                bad(i, f"{ident}: badge {badge!r} needs a label and a tone from {sorted(TONES)}")
        bad_platforms = [p for p in m.get("platforms", []) if p not in PLATFORMS]
        if bad_platforms:
            bad(i, f"{ident}: unknown platforms {bad_platforms}")
        for key in ("createdAt", "updatedAt"):
            if key in m and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", m[key]):
                bad(i, f"{ident}: {key} must be yyyy-MM-dd")
        vision = m.get("vision")
        if vision is not None and (fmt != "gguf" or not str(vision.get("mmprojFile", "")).endswith(".gguf")):
            bad(i, f"{ident}: vision needs a gguf entry and an mmprojFile ending in .gguf")

        if offline or not re.fullmatch(r"[0-9a-f]{40}", str(m.get("revision", ""))):
            continue
        try:
            files = tree(repo, m["revision"])
        except RuntimeError as error:
            bad(i, f"{ident}: {error}")
            continue
        if fmt == "gguf":
            remote = files.get(m["file"])
            if remote is None:
                bad(i, f"{ident}: {m['file']} is not in {repo} at {m['revision'][:8]}")
            else:
                if remote["size"] != m.get("sizeBytes"):
                    bad(i, f"{ident}: sizeBytes {m.get('sizeBytes')} but the file is {remote['size']}")
                if remote["sha256"] != m.get("sha256"):
                    bad(i, f"{ident}: sha256 {str(m.get('sha256'))[:12]} but the file is {str(remote['sha256'])[:12]}")
            if vision:
                projector = files.get(vision["mmprojFile"])
                if projector is None:
                    bad(i, f"{ident}: mmprojFile {vision['mmprojFile']} is not in the repo")
                elif vision.get("mmprojSize") not in (None, projector["size"]):
                    bad(i, f"{ident}: mmprojSize {vision.get('mmprojSize')} but the file is {projector['size']}")
        else:
            if not any(p.endswith(".safetensors") for p in files):
                bad(i, f"{ident}: no .safetensors files at {m['revision'][:8]}")
            actual = mlx_snapshot_size(files)
            if actual != m.get("sizeBytes"):
                bad(i, f"{ident}: sizeBytes {m.get('sizeBytes')} but the snapshot is {actual}")
    return problems


def cmd_check(args):
    offline = "--offline" in args
    paths = [a for a in args if not a.startswith("--")] or DEFAULT_FILES
    problems = []
    for path in paths:
        problems += check_file(path, offline)
    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} problem(s)")
        sys.exit(1)
    print(f"ok: {', '.join(paths)}" + (" (schema only, --offline)" if offline else ""))


if __name__ == "__main__":
    commands = {"add": cmd_add, "check": cmd_check}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: catalog.py add|check ...")
    commands[sys.argv[1]](sys.argv[2:])
