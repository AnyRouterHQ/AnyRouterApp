#!/usr/bin/env python3
"""Add a provider logo from lobe-icons (MIT) and register it in Design/model-brands.json.

Usage: scripts/logo-add.py <slug> <lobe-icon-name> "<Display name>"
  e.g. scripts/logo-add.py tencent tencent Tencent

Fetches the single-color SVG from the pinned @lobehub/icons-static-svg package, normalizes it for an
asset catalog (fixed 24x24, black fill, template rendering, vector preserved), writes
Design/Assets.xcassets/Logo-<slug>.imageset and adds the slug to the brand table. When the package has a
<lobe-icon-name>-color.svg too, it is written as LogoColor-<slug>.imageset (original colors; not "Logo-<slug>-color",
because Xcode drops a "Color" suffix when it names asset symbols and the two sets would clash) and listed under
"colorMarks": "any" draws it in light and dark mode, "light" (the mark has black in it, which vanishes on a dark
background) draws the single-color mark in dark mode instead. Do not draw logos by hand.
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


def contents(filename: str, template: bool) -> dict:
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template" if template else "original",
        },
    }


def fetch(name: str):
    url = f"https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@{LOBE_VERSION}/icons/{name}.svg"
    # curl, not urllib: python.org builds on macOS ship without a CA bundle.
    done = subprocess.run(["curl", "-fsSL", "--max-time", "30", url], capture_output=True, text=True)
    return done.stdout if done.returncode == 0 else None


def sized(svg: str) -> str:
    svg = svg.replace('height="1em"', 'height="24"').replace('width="1em"', 'width="24"')
    return re.sub(r'\s+style="[^"]*"', "", svg, count=1)


def normalize(svg: str) -> str:
    return sized(svg.replace('fill="currentColor"', 'fill="#000000"'))


def has_dark_fill(svg: str) -> bool:
    """True when some part of the color mark is black or near black (or left to currentColor)."""
    if "currentColor" in svg:
        return True
    for value in re.findall(r'(?:fill|stop-color)="#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})"', svg):
        if len(value) == 3:
            value = "".join(c * 2 for c in value)
        r, g, b = (int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
        if 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.2:
            return True
    return False


def write_set(name: str, filename: str, svg: str, template: bool) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / filename).write_text(svg, encoding="utf-8")
    (folder / "Contents.json").write_text(json.dumps(contents(filename, template), indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    slug, lobe, display = sys.argv[1:]
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug) or not re.fullmatch(r"[a-z0-9]+", lobe):
        sys.exit("slug and lobe-icon name must be lowercase ascii")
    mono = fetch(lobe)
    if mono is None:
        sys.exit(f"lobe-icons has no {lobe}.svg")
    svg = normalize(mono)
    if "currentColor" in svg or "1em" in svg:
        sys.exit(f"{lobe}.svg still has unnormalized values")
    write_set(f"Logo-{slug}", f"{slug}.svg", svg, template=True)

    table = json.loads(TABLE.read_text(encoding="utf-8"))
    table["brands"][slug] = display
    color = fetch(f"{lobe}-color")
    marks = table.setdefault("colorMarks", {})
    if color is not None:
        color = sized(color)
        write_set(f"LogoColor-{slug}", f"{slug}-color.svg", color, template=False)
        marks[slug] = "light" if has_dark_fill(color) else "any"
    table["colorMarks"] = dict(sorted(marks.items()))
    TABLE.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    kind = f", color mark ({marks[slug]})" if color is not None else ""
    print(f"added {slug} ({display}) from lobe-icons {lobe}{kind}")


main()
