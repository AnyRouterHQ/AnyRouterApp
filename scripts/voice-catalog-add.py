#!/usr/bin/env python3
"""Builds catalog/voice-models.json from Hugging Face folder listings.

Each downloadable voice model is a folder of files. This script pins the repo revision and writes every file with
its absolute URL, size and sha256 (the LFS oid), so the app downloads exactly these bytes and verifies them.
Run: python3 -I scripts/voice-catalog-add.py   (needs network; rewrites the Whisper entries, keeps the rest)
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "catalog" / "voice-models.json"
API = "https://huggingface.co/api/models/"

WHISPER_REPO = "argmaxinc/whisperkit-coreml"
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


def get(url):
    # curl uses the system certificate store; python.org builds of Python do not ship one.
    return json.loads(subprocess.run(["curl", "-fsSL", "--max-time", "60", url], check=True, capture_output=True).stdout)


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


def main():
    existing = json.loads(OUT.read_text()) if OUT.exists() else {"models": []}
    kept = [m for m in existing["models"] if m["engine"] != "whisperKit"]
    models = whisper_entries() + kept
    OUT.write_text(json.dumps({"version": 1, "models": models}, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {len(models)} voice models to {OUT}")


if __name__ == "__main__":
    main()
