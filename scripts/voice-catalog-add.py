#!/usr/bin/env python3
"""Builds catalog/voice-models.json from Hugging Face folder listings.

Each downloadable voice model is a folder of files. This script pins the repo revision and writes every file with
its absolute URL, size and sha256 (the LFS oid), so the app downloads exactly these bytes and verifies them.
Run: python3 -I scripts/voice-catalog-add.py [whisper] [ttskit]   (needs network). With no argument it rewrites every
group; with names it rewrites only those groups and keeps the other entries as they are. A group follows the head of
its Hugging Face repo, so rewrite only the one you are changing: the others stay on their pinned commit.
"""
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "catalog" / "voice-models.json"
API = "https://huggingface.co/api/models/"

WHISPER_REPO = "argmaxinc/whisperkit-coreml"
# WhisperKit loads its tokenizer from the model folder when tokenizer.json is there, and otherwise downloads it from
# Hugging Face at load time. The model folders on whisperkit-coreml do not carry it, so each entry adds these files.
TOKENIZER_FILES = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json"]
TOKENIZER_REPO = {
    "whisper-tiny": "openai/whisper-tiny",
    "whisper-base": "openai/whisper-base",
    "whisper-small": "openai/whisper-small",
    "whisper-large-v3-turbo": "openai/whisper-large-v3",
}
WHISPER = [
    # id, folder, title, summary, order, weak languages (listed by the model, handled badly)
    ("whisper-tiny", "openai_whisper-tiny", "Whisper Tiny",
     "Smallest and fastest. Fine for English; too weak for Vietnamese, which uses the system engine.", 1, ["vi"]),
    ("whisper-base", "openai_whisper-base", "Whisper Base",
     "Fast and light. Fine for English and other widely spoken languages.", 2, []),
    ("whisper-small", "openai_whisper-small_216MB", "Whisper Small",
     "Balanced. Handles Vietnamese and most other languages.", 3, []),
    ("whisper-large-v3-turbo", "openai_whisper-large-v3-v20240930_626MB", "Whisper Large v3 Turbo",
     "Most accurate, compressed to 627 MB. Best on a phone with 8 GB or an iPad.", 4, []),
]


# TTSKit (Qwen3-TTS on Core ML). The folder layout is TTSKitConfig's: modelFolder/qwen3_tts/<component>/<versionDir>/<variant>/*.mlmodelc.
# The variants are Qwen3VariantDefaults in argmax-oss-swift v1.1.1, the ones TTSKit loads for the 0.6B model on iOS
# (the variant strings do not depend on the platform; only 0.6B is offered on iOS). Keep both in step with the pinned package.
TTSKIT_REPO = "argmaxinc/ttskit-coreml"
TTSKIT_VERSION_DIR = "12hz-0.6b-customvoice"
TTSKIT_COMPONENTS = [
    ("code_decoder", "W8A16-stateful"),
    ("multi_code_decoder", "W8A16-multifunction"),
    ("code_embedder", "W16A16"),
    ("multi_code_embedder", "W16A16"),
    ("text_projector", "W8A16"),
    ("speech_decoder", "W8A16-multifunction"),
]
# TTSKit loads its tokenizer from tokenizerFolder when tokenizer.json is there (the default is a Hub download of this repo).
# tokenizer_config.json is read with it, and its tokenizer_class (Qwen2Tokenizer) is what picks the tokenizer.
TTSKIT_TOKENIZER_REPO = "Qwen/Qwen3-0.6B"
TTSKIT_TOKENIZER_FILES = ["tokenizer.json", "tokenizer_config.json"]
# Qwen3Language in TTSKit, as language codes.
TTSKIT_LANGUAGES = ["en", "zh", "ja", "ko", "de", "fr", "ru", "pt", "es", "it"]


def get(url):
    # curl uses the system certificate store; python.org builds of Python do not ship one.
    return json.loads(subprocess.run(["curl", "-fsSL", "--max-time", "60", url], check=True, capture_output=True).stdout)


def fetch_bytes(url):
    return subprocess.run(["curl", "-fsSL", "--max-time", "120", url], check=True, capture_output=True).stdout


def tokenizer_files(entry_id):
    repo = TOKENIZER_REPO[entry_id]
    revision = get(API + repo)["sha"]
    files = []
    for name in TOKENIZER_FILES:
        url = f"https://huggingface.co/{repo}/resolve/{revision}/{name}"
        data = fetch_bytes(url)
        files.append({"path": name, "url": url, "sizeBytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    return files


def hf_file(repo, revision, remote_path, install_path, item):
    """One catalog file. A file stored in Git rather than LFS has no sha256 in the listing, so it is hashed here."""
    url = f"https://huggingface.co/{repo}/resolve/{revision}/{remote_path}"
    if "lfs" in item:
        return {"path": install_path, "url": url, "sizeBytes": item["lfs"]["size"], "sha256": item["lfs"]["oid"]}
    data = fetch_bytes(url)
    assert len(data) == item["size"], f"{remote_path}: listing says {item['size']} bytes, download is {len(data)}"
    return {"path": install_path, "url": url, "sizeBytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def ttskit_entries():
    revision = get(API + TTSKIT_REPO)["sha"]
    files = []
    for component, variant in TTSKIT_COMPONENTS:
        folder = f"qwen3_tts/{component}/{TTSKIT_VERSION_DIR}/{variant}"
        tree = get(f"{API}{TTSKIT_REPO}/tree/{revision}/{folder}?recursive=true")
        listed = [item for item in tree if item["type"] == "file"]
        assert listed, f"no files under {folder}"
        files += [hf_file(TTSKIT_REPO, revision, item["path"], item["path"], item) for item in listed]
    tokenizer_revision = get(API + TTSKIT_TOKENIZER_REPO)["sha"]
    tokenizer_tree = {item["path"]: item for item in get(f"{API}{TTSKIT_TOKENIZER_REPO}/tree/{tokenizer_revision}")}
    for name in TTSKIT_TOKENIZER_FILES:
        files.append(hf_file(TTSKIT_TOKENIZER_REPO, tokenizer_revision, name, name, tokenizer_tree[name]))
    files.sort(key=lambda f: f["path"])
    return [{
        "id": "ttskit-qwen3-0.6b",
        "kind": "tts",
        "engine": "ttsKit",
        "title": "Qwen3-TTS 0.6B",
        "summary": "Natural neural voices in 10 languages: English, Chinese, Japanese, Korean, German, French, Russian, "
                   "Portuguese, Spanish and Italian. Vietnamese is not covered, so it uses the system voice.",
        "languages": TTSKIT_LANGUAGES,
        "detectsLanguage": False,
        # Qwen3-TTS-12Hz-0.6B-CustomVoice is Apache-2.0 on its model card; argmax's Core ML conversion card states no licence.
        "license": "Apache-2.0",
        "sourceURL": f"https://huggingface.co/{TTSKIT_REPO}/tree/{revision}/qwen3_tts",
        "order": 1,
        "sizeBytes": sum(f["sizeBytes"] for f in files),
        "files": files,
    }]


def whisper_entries():
    revision = get(API + WHISPER_REPO)["sha"]
    entries = []
    for entry_id, folder, title, summary, order, weak in WHISPER:
        tree = get(f"{API}{WHISPER_REPO}/tree/{revision}/{folder}?recursive=true")
        files = []
        for item in tree:
            if item["type"] != "file":
                continue
            path = item["path"][len(folder) + 1:]
            file = {
                "path": path,
                "url": f"https://huggingface.co/{WHISPER_REPO}/resolve/{revision}/{folder}/{path}",
                "sizeBytes": item.get("lfs", {}).get("size", item["size"]),
            }
            if "lfs" in item:
                file["sha256"] = item["lfs"]["oid"]
            files.append(file)
        files += tokenizer_files(entry_id)
        files.sort(key=lambda f: f["path"])
        entry = {
            "id": entry_id,
            "kind": "stt",
            "engine": "whisperKit",
            "title": title,
            "summary": summary,
            "languages": ["*"],
            "languageCount": 99,
            "detectsLanguage": True,
            "license": "MIT",
            "sourceURL": f"https://huggingface.co/{WHISPER_REPO}/tree/{revision}/{folder}",
            "order": order,
            "sizeBytes": sum(f["sizeBytes"] for f in files),
            "files": files,
        }
        if weak:
            entry["weakLanguages"] = weak
        entries.append(entry)
    return entries


# Entry order in the file: each group, then everything else.
GROUPS = [("whisper", "whisperKit", whisper_entries), ("ttskit", "ttsKit", ttskit_entries)]


def main():
    wanted = set(sys.argv[1:])
    unknown = wanted - {name for name, _, _ in GROUPS}
    if unknown:
        sys.exit(f"unknown group {', '.join(sorted(unknown))}; choose from {', '.join(name for name, _, _ in GROUPS)}")
    existing = json.loads(OUT.read_text()) if OUT.exists() else {"models": []}
    engines = {engine for _, engine, _ in GROUPS}
    models = []
    for name, engine, build in GROUPS:
        if not wanted or name in wanted:
            models += build()
        else:
            models += [m for m in existing["models"] if m["engine"] == engine]
    models += [m for m in existing["models"] if m["engine"] not in engines]
    OUT.write_text(json.dumps({"version": 1, "models": models}, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {len(models)} voice models to {OUT}")


if __name__ == "__main__":
    main()
