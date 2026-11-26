"""Catalog tooling: add a model to catalog/models.json, or check every entry against Hugging Face.

Run through scripts/catalog-add.sh and scripts/catalog-check.sh (python3 -I, standard library only).
All HTTP goes through curl so the system certificate store is used.
"""
import json
import os
import re
import struct
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
    "isOnboarding", "platforms", "recommended", "minRAMBytes", "createdAt", "updatedAt", "memory",
}
MEMORY_KEYS = {"fullKVBytesPerToken", "windowKVBytesPerToken", "windowTokens", "activeFraction", "lazyWeightBytes"}

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


# ---- memory profile (KV cache bytes per token) ----------------------------------------------------------------

GGUF_SCALARS = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i", 6: "<f", 7: "<?", 10: "<Q", 11: "<q", 12: "<d"}


class _Short(Exception):
    pass


def _parse_gguf_metadata(data):
    """Metadata key/values of a GGUF header. Raises _Short when the bytes end before the metadata does."""
    pos = 0

    def take(n):
        nonlocal pos
        if pos + n > len(data):
            raise _Short()
        chunk = data[pos:pos + n]
        pos += n
        return chunk

    def string():
        return take(struct.unpack("<Q", take(8))[0]).decode("utf8", "replace")

    def value(kind):
        if kind in GGUF_SCALARS:
            fmt = GGUF_SCALARS[kind]
            return struct.unpack(fmt, take(struct.calcsize(fmt)))[0]
        if kind == 8:
            return string()
        if kind == 9:
            inner, count = struct.unpack("<IQ", take(12))
            return [value(inner) for _ in range(count)]
        raise ValueError(f"unknown GGUF value type {kind}")

    if take(4) != b"GGUF":
        raise ValueError("not a GGUF file")
    take(4)
    tensor_count, count = struct.unpack("<QQ", take(16))
    meta = {}
    for _ in range(count):
        key = string()
        kind = struct.unpack("<I", take(4))[0]
        item = value(kind)
        # Token tables are huge and not needed here.
        meta[key] = item if not (isinstance(item, list) and len(item) > 4096) else None
    tensors = []
    for _ in range(tensor_count):
        name = string()
        dimensions = struct.unpack("<I", take(4))[0]
        take(dimensions * 8 + 4)
        tensors.append((struct.unpack("<Q", take(8))[0], name))
    return meta, tensors


def gguf_header(repo, revision, file):
    """Metadata and tensor list of a remote GGUF, reading only as much of the file as the header needs."""
    for megabytes in (4, 16, 64, 192):
        out = subprocess.run(
            ["curl", "-fsSL", "--retry", "3", "-r", f"0-{megabytes * 1024 * 1024 - 1}",
             f"{HF}/{repo}/resolve/{revision}/{file}"],
            capture_output=True,
        )
        if out.returncode != 0:
            raise RuntimeError(f"cannot read the header of {repo}/{file}: curl exit {out.returncode}")
        try:
            return _parse_gguf_metadata(out.stdout)
        except _Short:
            continue
    raise RuntimeError(f"{repo}/{file}: the GGUF header is larger than 192 MB")


def lazy_weight_bytes(tensors):
    """Bytes of tables that mmap keeps out of RAM: the per-layer embeddings, and the token embeddings when the output
    matrix is a separate tensor. Sizes come from the gaps between tensor offsets. Same rule as GGUFHeader.lazyBytes."""
    ordered = sorted(tensors)
    sizes = {ordered[i][1]: ordered[i + 1][0] - ordered[i][0] for i in range(len(ordered) - 1)}
    lazy = sizes.get("per_layer_token_embd.weight", 0)
    if any(name == "output.weight" for _, name in ordered):
        lazy += sizes.get("token_embd.weight", 0)
    return lazy


def memory_from_gguf(meta):
    """KV bytes per token (f16 cache) split into full-attention and sliding-window layers, plus the expert share."""
    arch = meta.get("general.architecture")
    p = f"{arch}."
    try:
        layers = meta[p + "block_count"]
        heads = meta[p + "attention.head_count"]
        embedding = meta[p + "embedding_length"]
    except KeyError:
        return None
    kv_heads = meta.get(p + "attention.head_count_kv") or heads
    key_len, value_len = meta.get(p + "attention.key_length"), meta.get(p + "attention.value_length")
    key_swa = meta.get(p + "attention.key_length_swa") or key_len
    value_swa = meta.get(p + "attention.value_length_swa") or value_len
    window = meta.get(p + "attention.sliding_window") or 0
    pattern = meta.get(p + "attention.sliding_window_pattern")
    if pattern is None and window and arch in ("gemma3", "gemma3n"):
        pattern = 6  # llama.cpp's built-in default: five window layers, then one full layer
    shared = meta.get(p + "attention.shared_kv_layers") or 0

    def at(value, i):
        return value[i] if isinstance(value, list) else value

    def is_window(i):
        if not window or pattern is None:
            return False
        if isinstance(pattern, list):
            return bool(pattern[i])
        return i % pattern < pattern - 1

    full = windowed = 0
    for i in range(layers - shared):
        h, hk = at(heads, i), at(kv_heads, i)
        if not hk:
            continue  # a layer without attention keeps no KV cache
        swa = is_window(i)
        k = (key_swa if swa else key_len) or embedding // h
        v = (value_swa if swa else value_len) or embedding // h
        size = hk * (k + v) * 2
        if swa:
            windowed += size
        else:
            full += size
    result = {"fullKVBytesPerToken": full}
    if windowed:
        result["windowKVBytesPerToken"] = windowed
        result["windowTokens"] = window
    experts, used = meta.get(p + "expert_count") or 0, meta.get(p + "expert_used_count") or 0
    if experts > 1 and 0 < used <= experts:
        result["activeFraction"] = round(0.06 + 0.94 * used / experts, 3)
    return result


def memory_from_mlx_config(config):
    text = config.get("text_config") or config
    try:
        layers = text["num_hidden_layers"]
        heads = text["num_attention_heads"]
        hidden = text["hidden_size"]
    except KeyError:
        return None
    kv_heads = text.get("num_key_value_heads") or heads
    head_dim = text.get("head_dim") or hidden // heads
    global_dim = text.get("global_head_dim") or head_dim
    global_heads = text.get("num_global_key_value_heads") or kv_heads
    types = text.get("layer_types")
    window = text.get("sliding_window") or 0
    period = text.get("sliding_window_pattern")
    if not types and window and isinstance(period, int) and period > 1:
        types = ["sliding_attention" if i % period < period - 1 else "full_attention" for i in range(layers)]
    shared = text.get("num_kv_shared_layers") or 0
    full = windowed = 0
    for i in range(layers - shared):
        swa = bool(types and types[i] == "sliding_attention" and window)
        size = kv_heads * head_dim * 2 * 2 if swa or not types else global_heads * global_dim * 2 * 2
        if swa:
            windowed += size
        else:
            full += size
    result = {"fullKVBytesPerToken": full}
    if windowed:
        result["windowKVBytesPerToken"] = windowed
        result["windowTokens"] = window
    experts = text.get("num_experts") or text.get("num_local_experts") or 0
    used = text.get("num_experts_per_tok") or 0
    if experts > 1 and 0 < used <= experts:
        result["activeFraction"] = round(0.06 + 0.94 * used / experts, 3)
    return result


def memory_for_entry(entry):
    """The memory profile of an entry, read from the model's own metadata. None when the metadata lacks the keys."""
    if entry["format"] == "gguf":
        meta, tensors = gguf_header(entry["repo"], entry["revision"], entry["file"])
        memory = memory_from_gguf(meta)
        lazy = lazy_weight_bytes(tensors)
        if lazy:
            memory = (memory or {"fullKVBytesPerToken": 0}) | {"lazyWeightBytes": lazy}
        return memory
    config = fetch_json(f"{HF}/{entry['repo']}/resolve/{entry['revision']}/config.json")
    return memory_from_mlx_config(config)


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
    entry["revision"] = revision
    memory = memory_for_entry(entry)
    if memory:
        entry["memory"] = memory
    else:
        print("note: the model's metadata has no KV-cache keys; the app will estimate memory from the file size")

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
         "isOnboarding", "platforms", "recommended", "minRAMBytes", "memory", "createdAt", "updatedAt", "order"]


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
        if re.search(r"\b(RAM|GB|memory)\b", str(m.get("summary", "")), re.I):
            bad(i, f"{ident}: the summary must not make memory claims; the app derives them from the model's memory facts")
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
        memory = m.get("memory")
        if memory is not None:
            extra = set(memory) - MEMORY_KEYS
            if extra or not isinstance(memory.get("fullKVBytesPerToken"), int) or memory["fullKVBytesPerToken"] < 0:
                bad(i, f"{ident}: memory needs an integer fullKVBytesPerToken and only {sorted(MEMORY_KEYS)}")
            if memory.get("windowKVBytesPerToken") and not memory.get("windowTokens"):
                bad(i, f"{ident}: windowKVBytesPerToken needs windowTokens")
            fraction = memory.get("activeFraction")
            if fraction is not None and not (0 < fraction < 1):
                bad(i, f"{ident}: activeFraction must be between 0 and 1")
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


def cmd_memory(args):
    """Fill or refresh the memory profile of every entry in the given catalog files."""
    paths = [a for a in args if not a.startswith("--")] or DEFAULT_FILES
    for path in paths:
        full = os.path.join(ROOT, path)
        document = load(full)
        for entry in document["models"]:
            memory = memory_for_entry(entry)
            label = entry_id(entry)
            if memory is None:
                entry.pop("memory", None)
                print(f"{label}: no KV-cache keys in the metadata, the app will estimate")
            else:
                entry["memory"] = memory
                print(f"{label}: {memory}")
        document["models"] = [ordered(m) for m in document["models"]]
        save(full, document)


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
    commands = {"add": cmd_add, "check": cmd_check, "memory": cmd_memory}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: catalog.py add|check|memory ...")
    commands[sys.argv[1]](sys.argv[2:])
