"""Catalog tooling: add a model size to a family in catalog/models.json, or check every variant against Hugging Face.

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
SCHEMA_VERSION = 2
MLX_EXTENSIONS = {"safetensors", "json", "model", "txt", "jinja", "tiktoken"}
TONES = {"info", "success", "warning", "neutral"}
PLATFORMS = {"ios", "ipados"}
REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")
QUANT_RE = re.compile(r"(?i)(?<![A-Za-z0-9])((?:IQ|Q)\d(?:_[A-Z0-9]+)*|BF16|F16|F32)(?![A-Za-z0-9])")
KNOWN_KEYS = {
    "repo", "format", "file", "title", "summary", "parameters", "quantization", "sizeBytes", "contextLength",
    "license", "revision", "capabilities", "order", "sha256", "iconKey", "badges", "supportsThinking", "vision",
    "isOnboarding", "platforms", "recommended", "minRAMBytes", "createdAt", "updatedAt", "memory", "sampling",
}
MEMORY_KEYS = {"fullKVBytesPerToken", "windowKVBytesPerToken", "windowTokens", "activeFraction", "lazyWeightBytes"}
SAMPLING_KEYS = {"temperature": float, "topP": float, "topK": int, "minP": float, "maxOutputTokens": int}
# A publisher can rename a GGUF to ".gguf_file" so that tools which list "*.gguf" skip it (unsloth does this for files
# in a layout only newer llama.cpp loads). The app saves it as ".gguf".
GGUF_SUFFIXES = (".gguf", ".gguf_file")

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
    if entry["engine"] == "gguf":
        meta, tensors = gguf_header(entry["repo"], entry["revision"], entry["file"])
        memory = memory_from_gguf(meta)
        lazy = lazy_weight_bytes(tensors)
        if lazy:
            memory = (memory or {"fullKVBytesPerToken": 0}) | {"lazyWeightBytes": lazy}
        return memory
    config = fetch_json(f"{HF}/{entry['repo']}/resolve/{entry['revision']}/config.json")
    return memory_from_mlx_config(config)


def entry_id(variant):
    """The id the app uses for a variant: gguf/<repo>/<file> or mlx/<repo>. Installed models are found by it."""
    if variant.get("engine") == "gguf":
        return f"gguf/{variant['repo']}/{variant.get('file', '')}"
    return f"mlx/{variant['repo']}"


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


# ---- shapes --------------------------------------------------------------------------------------------------------
#
# catalog/models.json is {"schemaVersion": 2, "updatedAt", "families": [family]}.
# A family is a model line at one generation: id, name, publisher, line, logo, summary, website, tags, badges, status,
# replacedBy, order, variants. A variant is one downloadable size: repo, engine (gguf|mlx), file (gguf), params, quant,
# sizeBytes, contextLength, license, revision, sha256 (gguf), memory, and optional vision, isOnboarding, platforms,
# minRAMBytes, sampling, createdAt, updatedAt.

FAMILY_KEYS = ["id", "name", "publisher", "line", "logo", "summary", "website", "tags", "badges", "status",
               "replacedBy", "order", "variants"]
VARIANT_KEYS = ["repo", "engine", "file", "params", "quant", "sizeBytes", "contextLength", "license", "revision",
                "sha256", "vision", "isOnboarding", "platforms", "minRAMBytes", "sampling", "memory", "createdAt", "updatedAt"]
TAGS = {"thinking", "vision", "audio", "tools", "code", "multilingual", "mobile"}
BADGES = {"best", "recommended", "new", "experimental"}
STATUSES = {"current", "deprecated"}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def ordered_family(family):
    out = {k: family[k] for k in FAMILY_KEYS if k in family and k != "variants"}
    out["variants"] = [ordered_variant(v) for v in family.get("variants", [])]
    return out | {k: v for k, v in family.items() if k not in FAMILY_KEYS}


def ordered_variant(variant):
    return {k: variant[k] for k in VARIANT_KEYS if k in variant} | {k: v for k, v in variant.items() if k not in VARIANT_KEYS}


def all_variants(document):
    return [(family, variant) for family in document["families"] for variant in family["variants"]]


# ---- add -------------------------------------------------------------------------------------------------------

def cmd_add(args):
    options = {"--catalog": "catalog/models.json", "--family": None, "--params": None, "--revision": None,
               "--name": None, "--publisher": None, "--line": None, "--logo": None, "--summary": None,
               "--website": None, "--tags": None, "--status": "current", "--mmproj": None, "--image-side": None}
    flags = {"--mlx", "--onboarding", "--update"}
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
    if len(positional) != (1 if mlx else 2) or not options["--family"] or not options["--params"]:
        sys.exit("usage: catalog-add.sh <hf-repo> <file.gguf> --family ID --params 4B [options]\n"
                 "       catalog-add.sh <hf-repo> --mlx --family ID --params 4B [options]\n"
                 "options: --catalog PATH --revision SHA --onboarding --update --mmproj FILE [--image-side 896]\n"
                 "new family: --name N --publisher P --line L --logo KEY --summary S --website URL [--tags a,b]")
    repo = positional[0]
    file = None if mlx else positional[1]
    if not REPO_RE.match(repo) or ".." in repo:
        sys.exit(f"not a Hugging Face repo id: {repo}")

    info = model_info(repo)
    revision = options["--revision"] or info["sha"]
    files = tree(repo, revision)
    variant = {"repo": repo, "engine": "mlx" if mlx else "gguf"}
    if mlx:
        if not any(p.endswith(".safetensors") for p in files):
            sys.exit(f"{repo} has no .safetensors files at {revision}")
        size = mlx_snapshot_size(files)
        quant = None
        context = ((info.get("config") or {}).get("text_config") or info.get("config") or {}).get("max_position_embeddings")
        quant = "4-bit" if "4bit" in repo.lower() else ("8-bit" if "8bit" in repo.lower() else None)
    else:
        if file not in files:
            sys.exit(f"{file} is not in {repo} at {revision}. Files: " + ", ".join(sorted(p for p in files if p.endswith(GGUF_SUFFIXES))))
        meta = files[file]
        size = meta["size"]
        match = QUANT_RE.search(os.path.basename(file))
        quant = match.group(1).upper() if match else None
        context = (info.get("gguf") or {}).get("context_length")
        variant["file"] = file
        if not meta["sha256"]:
            sys.exit(f"{file} has no LFS sha256 at {revision}; refusing to add an unverifiable file")

    license_tag = next((t.split(":", 1)[1] for t in info.get("tags", []) if t.startswith("license:")), None)
    variant["params"] = options["--params"]
    if quant:
        variant["quant"] = quant
    variant["sizeBytes"] = size
    if context:
        variant["contextLength"] = context
    if license_tag:
        variant["license"] = license_tag
    variant["revision"] = revision
    if not mlx:
        variant["sha256"] = files[file]["sha256"]
    if options["--mmproj"]:
        if mlx:
            sys.exit("--mmproj is for GGUF sizes")
        projector = files.get(options["--mmproj"])
        if projector is None:
            sys.exit(f"{options['--mmproj']} is not in {repo} at {revision}")
        variant["vision"] = {"mmprojFile": options["--mmproj"], "mmprojSize": projector["size"]}
        if options["--image-side"]:
            variant["vision"]["imageSide"] = int(options["--image-side"])
    if "--onboarding" in given:
        variant["isOnboarding"] = True
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    variant["updatedAt"] = today
    memory = memory_for_entry(variant)
    if memory:
        variant["memory"] = memory
    else:
        print("note: the model's metadata has no KV-cache keys; the app will estimate memory from the file size")

    path = os.path.join(ROOT, options["--catalog"])
    document = load(path)
    family = next((f for f in document["families"] if f["id"] == options["--family"]), None)
    if family is None:
        needed = ["--name", "--publisher", "--line", "--logo", "--summary", "--website"]
        if any(not options[k] for k in needed):
            sys.exit(f"family {options['--family']} does not exist; to create it also pass {' '.join(needed)}")
        family = {"id": options["--family"], "name": options["--name"], "publisher": options["--publisher"],
                  "line": options["--line"], "logo": options["--logo"], "summary": options["--summary"],
                  "website": options["--website"], "tags": [t for t in (options["--tags"] or "").split(",") if t],
                  "badges": [], "status": options["--status"],
                  "order": max([f.get("order", -1) for f in document["families"]] + [-1]) + 1, "variants": []}
        document["families"].append(family)
    existing = next((i for i, v in enumerate(family["variants"]) if entry_id(v) == entry_id(variant)), None)
    if existing is not None and "--update" not in given:
        sys.exit(f"{entry_id(variant)} is already in family {family['id']}; pass --update to refresh it")
    if existing is not None:
        old = family["variants"][existing]
        variant["createdAt"] = old.get("createdAt", today)
        for key in ("isOnboarding", "platforms", "minRAMBytes", "vision", "sampling"):
            if key in old and key not in variant:
                variant[key] = old[key]
        family["variants"][existing] = ordered_variant(variant)
    else:
        variant["createdAt"] = today
        family["variants"].append(ordered_variant(variant))
    document["families"] = [ordered_family(f) for f in document["families"]]
    document["updatedAt"] = today
    save(path, document)
    print(f"{'updated' if existing is not None else 'added'} {entry_id(variant)} in {family['id']}: {size} bytes, rev {revision[:8]}"
          + ("" if mlx else f", sha256 {variant['sha256'][:12]}"))


# ---- check -----------------------------------------------------------------------------------------------------

def check_file(path, offline):
    problems = []

    def bad(where, message):
        problems.append(f"{path}{where}: {message}")

    try:
        document = load(os.path.join(ROOT, path))
    except (OSError, ValueError) as error:
        return [f"{path}: cannot read: {error}"]
    if document.get("schemaVersion") != SCHEMA_VERSION:
        bad("", f"schemaVersion must be {SCHEMA_VERSION}, got {document.get('schemaVersion')!r}")
    families = document.get("families")
    if not isinstance(families, list) or not families:
        bad("", "families must be a non-empty list")
        return problems

    family_ids = {}
    lines = {}
    seen = {}
    for f_index, family in enumerate(families):
        where = f"[{family.get('id', f_index)}]"
        unknown = set(family) - set(FAMILY_KEYS)
        if unknown:
            bad(where, f"unknown family keys {sorted(unknown)}")
        fid = str(family.get("id", ""))
        if not ID_RE.match(fid):
            bad(where, f"family id {fid!r} must be lowercase letters, digits and dashes")
        if fid in family_ids:
            bad(where, f"duplicate family id {fid}")
        family_ids[fid] = family
        for key in ("name", "publisher", "line", "logo", "summary"):
            if not str(family.get(key, "")).strip():
                bad(where, f"{key} is missing")
        if re.search(r"\b(RAM|GB|memory)\b", str(family.get("summary", "")), re.I):
            bad(where, "the summary must not make memory claims; the app derives them from the variants' memory facts")
        if not str(family.get("website", "")).startswith("https://"):
            bad(where, "website must be an https URL")
        status = family.get("status")
        if status not in STATUSES:
            bad(where, f"status must be one of {sorted(STATUSES)}, got {status!r}")
        bad_tags = [t for t in family.get("tags", []) if t not in TAGS]
        if bad_tags:
            bad(where, f"unknown tags {bad_tags}; allowed {sorted(TAGS)}")
        bad_badges = [b for b in family.get("badges", []) if b not in BADGES]
        if bad_badges:
            bad(where, f"unknown badges {bad_badges}; allowed {sorted(BADGES)}")
        if status == "current":
            line = family.get("line")
            if line in lines:
                bad(where, f"line {line!r} already has a current family ({lines[line]}); deprecate the older generation")
            lines[line] = fid
            if family.get("replacedBy"):
                bad(where, "a current family has no replacedBy")
        variants = family.get("variants")
        if not isinstance(variants, list) or not variants:
            bad(where, "variants must be a non-empty list")
            continue
        for v_index, m in enumerate(variants):
            vw = f"{where}.variants[{v_index}]"
            unknown = set(m) - set(VARIANT_KEYS)
            if unknown:
                bad(vw, f"unknown keys {sorted(unknown)}")
            engine = m.get("engine")
            repo = m.get("repo", "")
            if engine not in ("gguf", "mlx"):
                bad(vw, f"engine must be gguf or mlx, got {engine!r}")
                continue
            if not REPO_RE.match(repo) or ".." in repo:
                bad(vw, f"invalid repo {repo!r}")
                continue
            if engine == "gguf" and not str(m.get("file", "")).endswith(GGUF_SUFFIXES):
                bad(vw, "a gguf variant needs a file ending in .gguf (or .gguf_file)")
                continue
            ident = entry_id(m)
            if ident in seen:
                bad(vw, f"duplicate id {ident} (also {seen[ident]})")
            seen[ident] = f"{fid}"
            if not str(m.get("params", "")).strip():
                bad(vw, f"{ident}: params is missing (for example 4B)")
            if not isinstance(m.get("sizeBytes"), int) or m["sizeBytes"] <= 0:
                bad(vw, f"{ident}: sizeBytes must be a positive integer")
            if not re.fullmatch(r"[0-9a-f]{40}", str(m.get("revision", ""))):
                bad(vw, f"{ident}: revision must be a 40-character commit sha, not a branch")
            if engine == "gguf" and not re.fullmatch(r"[0-9a-f]{64}", str(m.get("sha256", ""))):
                bad(vw, f"{ident}: sha256 must be 64 lowercase hex characters")
            if "sha256" in m and engine == "mlx":
                bad(vw, f"{ident}: sha256 applies to a single file; leave it out for MLX")
            if status == "current" and not m.get("memory"):
                bad(vw, f"{ident}: a current variant needs memory facts (run scripts/catalog-memory.sh)")
            bad_platforms = [p for p in m.get("platforms", []) if p not in PLATFORMS]
            if bad_platforms:
                bad(vw, f"{ident}: unknown platforms {bad_platforms}")
            for key in ("createdAt", "updatedAt"):
                if key in m and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", m[key]):
                    bad(vw, f"{ident}: {key} must be yyyy-MM-dd")
            memory = m.get("memory")
            if memory is not None:
                extra = set(memory) - MEMORY_KEYS
                if extra or not isinstance(memory.get("fullKVBytesPerToken"), int) or memory["fullKVBytesPerToken"] < 0:
                    bad(vw, f"{ident}: memory needs an integer fullKVBytesPerToken and only {sorted(MEMORY_KEYS)}")
                if memory.get("windowKVBytesPerToken") and not memory.get("windowTokens"):
                    bad(vw, f"{ident}: windowKVBytesPerToken needs windowTokens")
                fraction = memory.get("activeFraction")
                if fraction is not None and not (0 < fraction < 1):
                    bad(vw, f"{ident}: activeFraction must be between 0 and 1")
            sampling = m.get("sampling")
            if sampling is not None:
                wrong = [k for k, v in sampling.items()
                         if k not in SAMPLING_KEYS or isinstance(v, bool) or not isinstance(v, (int, float))
                         or (SAMPLING_KEYS[k] is int and not isinstance(v, int)) or v < 0]
                if engine != "gguf" or wrong or not sampling:
                    bad(vw, f"{ident}: sampling is for gguf sizes, with non-negative {sorted(SAMPLING_KEYS)} only")
            vision = m.get("vision")
            if vision is not None and (engine != "gguf" or not str(vision.get("mmprojFile", "")).endswith(".gguf")):
                bad(vw, f"{ident}: vision needs a gguf variant and an mmprojFile ending in .gguf")
            if vision is not None and not (isinstance(vision.get("mmprojSize"), int) and vision["mmprojSize"] > 0):
                bad(vw, f"{ident}: vision needs the integer mmprojSize of the projector")
            if vision is not None and "imageSide" in vision and not (isinstance(vision["imageSide"], int) and 224 <= vision["imageSide"] <= 4096):
                bad(vw, f"{ident}: vision.imageSide must be an integer between 224 and 4096")
            if vision is not None and "vision" not in family.get("tags", []):
                bad(vw, f"{ident}: a size with a projector needs the family tag vision")

            if offline or not re.fullmatch(r"[0-9a-f]{40}", str(m.get("revision", ""))):
                continue
            try:
                files = tree(repo, m["revision"])
            except RuntimeError as error:
                bad(vw, f"{ident}: {error}")
                continue
            if engine == "gguf":
                remote = files.get(m["file"])
                if remote is None:
                    bad(vw, f"{ident}: {m['file']} is not in {repo} at {m['revision'][:8]}")
                else:
                    if remote["size"] != m.get("sizeBytes"):
                        bad(vw, f"{ident}: sizeBytes {m.get('sizeBytes')} but the file is {remote['size']}")
                    if remote["sha256"] != m.get("sha256"):
                        bad(vw, f"{ident}: sha256 {str(m.get('sha256'))[:12]} but the file is {str(remote['sha256'])[:12]}")
                if vision:
                    projector = files.get(vision["mmprojFile"])
                    if projector is None:
                        bad(vw, f"{ident}: mmprojFile {vision['mmprojFile']} is not in the repo")
                    elif vision.get("mmprojSize") not in (None, projector["size"]):
                        bad(vw, f"{ident}: mmprojSize {vision.get('mmprojSize')} but the file is {projector['size']}")
            else:
                if not any(p.endswith(".safetensors") for p in files):
                    bad(vw, f"{ident}: no .safetensors files at {m['revision'][:8]}")
                actual = mlx_snapshot_size(files)
                if actual != m.get("sizeBytes"):
                    bad(vw, f"{ident}: sizeBytes {m.get('sizeBytes')} but the snapshot is {actual}")

    # A deprecated family must say what replaces it, and that must be a current family.
    for fid, family in family_ids.items():
        if family.get("status") == "deprecated":
            target = family.get("replacedBy")
            if not target:
                bad(f"[{fid}]", "a deprecated family needs replacedBy")
            elif target not in family_ids or family_ids[target].get("status") != "current":
                bad(f"[{fid}]", f"replacedBy {target!r} must be a current family in this file")
    return problems


def cmd_memory(args):
    """Fill or refresh the memory facts of every variant in the given catalog files."""
    paths = [a for a in args if not a.startswith("--")] or DEFAULT_FILES
    for path in paths:
        full = os.path.join(ROOT, path)
        document = load(full)
        for family, variant in all_variants(document):
            memory = memory_for_entry(variant)
            label = entry_id(variant)
            if memory is None:
                variant.pop("memory", None)
                print(f"{label}: no KV-cache keys in the metadata, the app will estimate")
            else:
                variant["memory"] = memory
                print(f"{label}: {memory}")
        document["families"] = [ordered_family(f) for f in document["families"]]
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
