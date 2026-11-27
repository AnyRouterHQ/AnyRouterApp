#!/usr/bin/env python3
"""Which model owners and local repos resolve to no logo?

Reads the brand table the app ships (Design/model-brands.json), the owner list of the live AnyRouter
catalog (Tests/Fixtures/anyrouter-owners.json) and the local catalog (catalog/models.json), and mirrors
ModelBrand's resolution. An owner counts when it has a bundled mark. An owner without one must be listed
under "noMark" in the table (it was reviewed: no public mark, shown as a letter monogram).

Usage:
  scripts/logo-coverage.py            report, exit 1 on an unreviewed owner or a local repo without a mark
  scripts/logo-coverage.py --refresh  re-fetch the live model list into the fixture first
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "Design" / "model-brands.json"
FIXTURE = ROOT / "Tests" / "Fixtures" / "anyrouter-owners.json"
CATALOG = ROOT / "catalog" / "models.json"
API = "https://anyrouter.dev/api/v1/models"
ROUTER_OWNER = "anyrouter"  # shows the AnyRouter mark, not a table entry


def refresh() -> None:
    # curl, not urllib: python.org builds on macOS ship without a CA bundle.
    body = subprocess.run(["curl", "-fsSL", "--max-time", "60", API], check=True, capture_output=True, text=True).stdout
    ids = sorted({m["id"] for m in json.loads(body)["data"]})
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps({"source": API, "ids": ids}, indent=1) + "\n", encoding="utf-8")
    print(f"fixture: {len(ids)} model ids")


def owner_mark(table: dict, owner: str):
    key = owner.lower()
    slug = table["aliases"].get(key, key)
    return slug if slug in table["brands"] else None


def family_mark(table: dict, bare: str):
    name = bare.lower()
    return next((f["slug"] for f in table["families"] if name.startswith(f["prefix"])), None)


def symbol_family(table: dict, bare: str):
    name = bare.lower()
    return next((f["symbol"] for f in table["symbols"] if name.startswith(f["prefix"])), None)


def main() -> int:
    if "--refresh" in sys.argv:
        refresh()
    table = json.loads(TABLE.read_text(encoding="utf-8"))
    ids = json.loads(FIXTURE.read_text(encoding="utf-8"))["ids"]
    by_owner: dict = {}
    for model_id in ids:
        owner, _, rest = model_id.partition("/")
        by_owner.setdefault(owner, []).append(rest.split("/")[-1])

    marked, monogram, unreviewed = [], [], []
    for owner in sorted(by_owner):
        if owner == ROUTER_OWNER or owner_mark(table, owner):
            marked.append(owner)
        elif owner in table["noMark"]:
            monogram.append(owner)
        else:
            unreviewed.append(owner)
    stale = [o for o in table["noMark"] if o not in by_owner or owner_mark(table, o)]
    by_model = sum(
        1 for owner, names in by_owner.items() for name in names
        if owner == ROUTER_OWNER or owner_mark(table, owner) or family_mark(table, name)
    )
    total = len(by_owner)
    print(f"owners with a mark: {len(marked)}/{total}")
    print(f"models with a mark (owner or family): {by_model}/{len(ids)}")
    print(f"owners shown as a monogram ({len(monogram)}): {' '.join(monogram)}")

    failed = False
    if unreviewed:
        failed = True
        print(f"::error::owners with no logo and not reviewed ({len(unreviewed)}): {' '.join(unreviewed)}")
        print("Add a mark with scripts/logo-add.py (and an alias if needed), or list the owner under noMark in Design/model-brands.json.")
    if stale:
        failed = True
        print(f"::error::noMark lists owners that are gone or now have a mark: {' '.join(stale)}")

    local = []
    for family in json.loads(CATALOG.read_text(encoding="utf-8"))["families"]:
        for variant in family["variants"]:
            owner, _, repo = variant["repo"].partition("/")
            if not (family_mark(table, repo) or owner_mark(table, owner) or symbol_family(table, repo)):
                local.append(variant["repo"])
    if local:
        failed = True
        print(f"::error::local catalog repos with no logo: {' '.join(sorted(set(local)))}")
    return 1 if failed else 0


sys.exit(main())
