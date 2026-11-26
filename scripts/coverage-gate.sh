#!/usr/bin/env bash
# Per-folder line coverage report and gate.
# Usage: scripts/coverage-gate.sh <Result.xcresult> [--report-only]
# Ratchet: fails when a gated file drops below its baseline in scripts/coverage-baseline.txt, or a file not listed there is below 100%. Files that cannot run on the Simulator are listed,
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

# Ratchet: scripts/coverage-baseline.txt lists gated files that are below 100% today ("path covered lines").
# A listed file may not drop below its baseline; any other gated file must be at 100%.
# Without a baseline file the gate only reports.
baseline = {}
baseline_path = os.path.join(root, "scripts/coverage-baseline.txt")
has_baseline = os.path.exists(baseline_path)
if has_baseline:
    for raw in open(baseline_path):
        parts = raw.split()
        if len(parts) == 3 and not raw.startswith("#"):
            baseline[parts[0]] = (int(parts[1]), int(parts[2]))

def regressed(rel, c, e):
    base = baseline.get(rel)
    if base is None:
        return True
    return c * base[1] < base[0] * e  # c/e < base_c/base_e

regressions = [f for f in failures if has_baseline and regressed(*f)]

generated = "\n".join(f"{rel} {c} {e}" for rel, c, e in sorted(failures)) + "\n"
with open(os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "coverage-baseline.generated.txt"), "w") as f:
    f.write("# Gated files below 100% lines: path covered lines. Regenerate from a complete main run.\n" + generated)

lines += ["", "## Coverage ratchet", ""]
lines.append("Baseline: " + (f"{len(baseline)} file(s)" if has_baseline else "none yet, report only"))
if failures:
    lines += ["| File | Covered | Lines | Baseline | Status | Uncovered functions |", "|---|---:|---:|---:|---|---|"]
    for rel, c, e in failures:
        uncovered = []
        note = ""
        proc = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", "--functions-for-file",
                               os.path.join(root, rel), result], capture_output=True, text=True)
        try:
            for t in json.loads(proc.stdout):
                functions = t.get("functions") or [fn for fl in t.get("files", []) for fn in fl.get("functions", [])]
                for fn in functions:
                    if fn["coveredLines"] < fn["executableLines"]:
                        name = fn["name"].replace("|", "/")
                        uncovered.append(f"{name} (line {fn['lineNumber']}, {fn['coveredLines']}/{fn['executableLines']})")
        except (ValueError, TypeError, KeyError):
            note = (proc.stderr or proc.stdout).strip().replace("|", "/").replace("\n", " ")[:160]
        if not uncovered and not note:
            note = "raw: " + proc.stdout.strip().replace("|", "/").replace("\n", " ")[:300]
        base = baseline.get(rel)
        base_text = f"{base[0]}/{base[1]}" if base else "-"
        status = "REGRESSED" if (rel, c, e) in regressions else "ok"
        lines.append(f"| {rel} | {c} | {e} | {base_text} | {status} | {'; '.join(uncovered) or note or 'no data'} |")
else:
    lines.append("All gated files are at 100% of lines.")
lines += ["", "<details><summary>coverage-baseline.txt for this run</summary>", "", "```", generated.rstrip(), "```", "</details>"]

lines += ["", "## Excluded (cannot run on the Simulator)", "", "| File | Reason |", "|---|---|"]
lines += [f"| {p} | {r} |" for p, r in sorted(exclusions.items())]

text = "\n".join(lines) + "\n"
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a") as f:
        f.write(text)

if regressions and mode != "--report-only":
    print(f"::error::{len(regressions)} gated file(s) below their coverage baseline or new under 100%")
    sys.exit(1)
PY
