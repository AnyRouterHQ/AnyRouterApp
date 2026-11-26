#!/usr/bin/env python3
"""Copies the screenshot attachments of an .xcresult into a folder as <prefix>-<attachment name>.png.

Used for the Mac capture: an iOS app running on a Mac cannot write outside its container, so
ScreenshotTests attach every capture and this script pulls them out of the result bundle.
Usage: export-xcresult-screenshots.py <Result.xcresult> <output dir> <prefix>
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

result, out_dir, prefix = sys.argv[1:4]
out = pathlib.Path(out_dir)
out.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", tmp], check=True)
    manifest = json.loads((pathlib.Path(tmp) / "manifest.json").read_text())
    copied = 0
    for test in manifest:
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            # Xcode appends _<index>_<UUID> and the extension to the attachment's name.
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)?$", "", name)
            source = pathlib.Path(tmp) / item["exportedFileName"]
            if not name or source.suffix.lower() != ".png":
                continue
            shutil.copy(source, out / f"{prefix}-{name}.png")
            copied += 1
print(f"{copied} screenshots exported")
sys.exit(0 if copied else 1)
