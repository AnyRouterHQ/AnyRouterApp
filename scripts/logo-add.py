#!/usr/bin/env python3
"""Add a monochrome provider logo from lobe-icons (MIT) and register it in Design/model-brands.json.

Usage: scripts/logo-add.py <slug> <lobe-icon-name> "<Display name>"
  e.g. scripts/logo-add.py tencent tencent Tencent

Fetches the single-color SVG from the pinned @lobehub/icons-static-svg package, normalizes it for an
asset catalog (fixed 24x24, black fill, template rendering, vector preserved), writes
Design/Assets.xcassets/Logo-<slug>.imageset and adds the slug to the brand table. Do not draw logos by hand.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

LOBE_VERSION = "1.106.0"
ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "Design" / "model-brands.json"
ASSETS = ROOT / "Design" / "Assets.xcassets"

CONTENTS = {
    "images": [{"filename": None, "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
}


def normalize(svg: str) -> str:
    svg = svg.replace('fill="currentColor"', 'fill="#000000"')
    svg = svg.replace('height="1em"', 'height="24"').replace('width="1em"', 'width="24"')
    return re.sub(r'\s+style="[^"]*"', "", svg, count=1)


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    slug, lobe, display = sys.argv[1:]
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug) or not re.fullmatch(r"[a-z0-9]+", lobe):
        sys.exit("slug and lobe-icon name must be lowercase ascii")
    url = f"https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@{LOBE_VERSION}/icons/{lobe}.svg"
    # curl, not urllib: python.org builds on macOS ship without a CA bundle.
    svg = normalize(subprocess.run(["curl", "-fsSL", "--max-time", "30", url], check=True, capture_output=True, text=True).stdout)
    if "currentColor" in svg or "1em" in svg:
        sys.exit(f"{lobe}.svg still has unnormalized values")
    folder = ASSETS / f"Logo-{slug}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{slug}.svg").write_text(svg, encoding="utf-8")
    contents = json.loads(json.dumps(CONTENTS))
    contents["images"][0]["filename"] = f"{slug}.svg"
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    table = json.loads(TABLE.read_text(encoding="utf-8"))
    table["brands"][slug] = display
    TABLE.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"added {slug} ({display}) from lobe-icons {lobe}")


main()
