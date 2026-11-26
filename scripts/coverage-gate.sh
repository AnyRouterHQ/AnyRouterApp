#!/usr/bin/env bash
# Per-folder line coverage report and gate.
# Usage: scripts/coverage-gate.sh <Result.xcresult> [--report-only]
# Fails when a gated file is below 100% lines. Files that cannot run on the Simulator are listed,
# with a reason each, in scripts/coverage-exclusions.txt; only those are skipped.
set -euo pipefail

RESULT="${1:?usage: coverage-gate.sh <Result.xcresult> [--report-only]}"
MODE="${2:-gate}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

JSON="${RUNNER_TEMP:-/tmp}/coverage.json"
xcrun xccov view --report --json "$RESULT" > "$JSON"

python3 -I - "$JSON" "$RESULT" "$ROOT" "$MODE" <<'PY'
import fnmatch, json, os, re, subprocess, sys

report_path, result, root, mode = sys.argv[1:5]
report = json.load(open(report_path))

GATED_GLOBS = [
    "Core/*",
    "Features/*Logic.swift",
    "Features/*Store.swift",
    "Features/*Model.swift",
    "Engines/AnyRouter/*",
    "Engines/Local/Catalog/*",
    "Engines/Local/Downloads/*",
    "Engines/Apple/ApplePrompt.swift",
    "Engines/Apple/SnapshotDeltaTracker.swift",
]

exclusions = {}
with open(os.path.join(root, "scripts/coverage-exclusions.txt")) as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        path, _, reason = line.partition("#")
        path, reason = path.strip(), reason.strip()
        if not reason:
            sys.exit("coverage-exclusions.txt: entry without a reason: " + path)
        exclusions[path] = reason

files = {}
for target in report["targets"]:
    if not target["name"].startswith("AnyRouter.app"):
        continue
    for f in target["files"]:
        rel = os.path.relpath(f["path"], root)
        files[rel] = (f["coveredLines"], f["executableLines"])

missing = [p for p in exclusions if not os.path.exists(os.path.join(root, p))]
if missing:
    sys.exit("coverage-exclusions.txt lists files that do not exist: " + ", ".join(missing))

def pct(c, e):
    return 100.0 if e == 0 else 100.0 * c / e

def gated(rel):
    return any(fnmatch.fnmatch(rel, g) for g in GATED_GLOBS)

# Features and Engines report one level deeper than the top folder.
def folder(rel):
    parts = rel.split("/")
    depth = 2 if parts[0] in ("Features", "Engines") and len(parts) > 2 else 1
    return "/".join(parts[:depth])

folders = {}
for rel, (c, e) in files.items():
    cc, ee = folders.get(folder(rel), (0, 0))
    folders[folder(rel)] = (cc + c, ee + e)

lines = ["## Unit test line coverage", "", "| Folder | Covered | Lines | Coverage |", "|---|---:|---:|---:|"]
tc = te = 0
for name in sorted(folders):
    c, e = folders[name]
    tc += c; te += e
    lines.append(f"| {name}/ | {c} | {e} | {pct(c, e):.1f}% |")
lines.append(f"| **App target** | {tc} | {te} | {pct(tc, te):.1f}% |")

failures = []
for rel in sorted(files):
    if not gated(rel) or rel in exclusions:
        continue
    c, e = files[rel]
    if e and c < e:
        failures.append((rel, c, e))

# A gated file with no coverage data never ran: treat as uncovered.
for dirpath, _, names in os.walk(root):
    for n in names:
        rel = os.path.relpath(os.path.join(dirpath, n), root)
        if rel.endswith(".swift") and rel.split("/")[0] in ("Core", "Features", "Engines") \
                and gated(rel) and rel not in files and rel not in exclusions:
            failures.append((rel, 0, 0))

lines += ["", "## 100% gate", ""]
if failures:
    lines += ["| File | Covered | Lines | Uncovered lines |", "|---|---:|---:|---|"]
    for rel, c, e in failures:
        uncovered = []
        out = subprocess.run(["xcrun", "xccov", "view", "--file", os.path.join(root, rel), result],
                             capture_output=True, text=True).stdout
        for m in re.finditer(r"^\s*(\d+):\s+(\d+)", out, re.M):
            if int(m.group(2)) == 0:
                uncovered.append(int(m.group(1)))
        lines.append(f"| {rel} | {c} | {e} | {', '.join(map(str, uncovered)) or 'no data'} |")
else:
    lines.append("All gated files are at 100% of lines.")

lines += ["", "## Excluded (cannot run on the Simulator)", "", "| File | Reason |", "|---|---|"]
lines += [f"| {p} | {r} |" for p, r in sorted(exclusions.items())]

text = "\n".join(lines) + "\n"
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a") as f:
        f.write(text)

if failures and mode != "--report-only":
    print(f"::error::{len(failures)} gated file(s) below 100% line coverage")
    sys.exit(1)
PY
