#!/usr/bin/env python3
"""Automatic UX scorecard for the AnyRouter app screenshots.

Usage:
  ux-score.py --screenshots DIR --evidence DIR --out ux-score.json --summary ux-score.md
              [--previous prev.json] [--device TAG] [--no-judge] [--max-judged N] [--model ID]
              [--commit SHA] [--run-url URL]

Inputs (the artifacts of screenshots.yml and verify-ui.yml, either or both):
  --screenshots  flat folder of <Simulator-Name>-<light|dark>-<screen>.png
  --evidence     folder of <device>/<journey>/<pass>-<NN>-<step>.png with <device>/results.tsv and audit.tsv
Scores 0 to 5 per criterion of docs/ux-rubric.md, from two scorers:
  deterministic  accessibility audit findings, native-first ratchet counts of the owning files, pixel checks
  judge          a vision model through the AnyRouter API (needs ANYROUTER_E2E_API_KEY, skipped with a note without it)
Report only: the exit code is 0 unless the arguments are wrong. See docs/ux-rubric.md for the scales.
"""
import argparse
import base64
import collections
import concurrent.futures
import csv
import datetime
import io
import json
import math
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RUBRIC_PATH = ROOT / "docs" / "ux-rubric.md"
OWNERS_PATH = ROOT / "scripts" / "ux-owners.json"
NATIVE_PATTERN = re.compile(
    r"ARColor\.|\.font\(\.ar|RoundedRectangle\(cornerRadius|Capsule\(\)|\.onTapGesture|\.shadow\(|"
    r"ARIconButton|ARSearchField|ARChip|ARSectionTitle"
)
API_BASE = "https://anyrouter.dev/api/v1"
DEFAULT_MODEL = "anyrouter/auto"
DEVICE_ORDER = ["iphone", "ipad-pro", "ipad-mini", "ipad", "mac"]
SCALE = {"iphone": 3, "ipad-pro": 2, "ipad-mini": 2, "ipad": 2, "mac": 2}
CHAT_LIKE = re.compile(r"chat|home|reply|replied|response|markdown|conversation|typed|composer")
DRAWER_LIKE = re.compile(r"drawer|thread-list")
SHOT_RE = re.compile(r"^(?P<dev>.+?)-(?P<variant>light|dark)-(?P<screen>.+)\.png$")


# ---------------------------------------------------------------- rubric and owners

def load_rubric(path=RUBRIC_PATH):
    """Returns (version, criteria ids in order, ids judged by the vision model, full text)."""
    text = Path(path).read_text()
    version = int(re.search(r"^Rubric version: (\d+)", text, re.M).group(1))
    heads = re.findall(r"^### \x60(\w+)\x60( \(audit only\))?", text, re.M)
    criteria = [h[0] for h in heads]
    judged = [h[0] for h in heads if not h[1]]
    return version, criteria, judged, text


def load_owners(path=OWNERS_PATH):
    return [(re.compile(o["match"]), o) for o in json.loads(Path(path).read_text())["owners"]]


def owner_of(owners, screen):
    for pattern, owner in owners:
        if pattern.search(screen):
            return {"lane": owner["lane"], "files": owner["files"]}
    return {"lane": "unassigned", "files": []}


# ---------------------------------------------------------------- collecting screens

def classify_device(name):
    lowered = name.lower()
    for prefix, tag in (("iphone", "iphone"), ("ipad-pro", "ipad-pro"), ("ipad-mini", "ipad-mini"),
                        ("ipad", "ipad"), ("mac", "mac")):
        if lowered.startswith(prefix):
            return tag
    return re.sub(r"[^a-z0-9]+", "-", lowered).strip("-") or "unknown"


def _screen(device, screen, variant, source, png, audit=None):
    return {"key": f"{device}:{screen}@{variant}", "device": device, "screen": screen, "variant": variant,
            "source": source, "png": png, "audit": audit}


def collect_screenshots(folder, device_override=None):
    screens = []
    for png in sorted(Path(folder).glob("*.png")):
        match = SHOT_RE.match(png.name)
        if not match:
            print(f"::warning::ux-score: skipped {png.name}, not <device>-<light|dark>-<screen>.png")
            continue
        device = device_override or classify_device(match["dev"])
        screens.append(_screen(device, match["screen"], match["variant"], "screenshots", str(png)))
    return screens


def _tsv(path, columns):
    """Rows of a tab separated file. An audit finding can hold the element label, with its own line breaks: a line
    with fewer fields than a row has continues the last field of the row before it."""
    if not path.exists():
        return []
    rows = []
    with path.open(newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) >= columns or not rows:
                if row:
                    rows.append(row)
            elif any(row):
                rows[-1][columns - 1 if len(rows[-1]) > columns - 1 else -1] += " " + " ".join(row).strip()
    return rows


def collect_evidence(folder, device_override=None):
    """One screen per results.tsv row. audited.tsv lists every audit call (journey, pass, name, step number) and
    audit.tsv its findings, so a step audited with no findings scores a clean 5 and an unaudited step gets no audit
    score. Older artifacts have neither the step number nor audited.tsv: findings then match a step by name.
    Findings that match no step become screens without a PNG."""
    screens = []
    for device_dir in sorted(p for p in Path(folder).iterdir() if p.is_dir()):
        device = device_override or classify_device(device_dir.name)
        by_step, by_journey = {}, collections.defaultdict(list)
        for journey, pass_name, number, name, png in (r[:5] for r in _tsv(device_dir / "results.tsv", 5)):
            path = device_dir / png
            screen = _screen(device, f"{journey}/{name}", pass_name, "verify", str(path) if path.exists() else None)
            by_step[(journey, pass_name, int(number))] = screen
            by_journey[(journey, pass_name)].append((name, screen))
            screens.append(screen)

        def find(row):
            journey, pass_name, name = row[:3]
            if len(row) > 3 and row[-1].isdigit():
                return by_step.get((journey, pass_name, int(row[-1])))
            names = by_journey.get((journey, pass_name), [])
            return next((s for n, s in names if n == name), None) or next(
                (s for n, s in names if n.startswith(name) or name.startswith(n)), None)

        for row in _tsv(device_dir / "audited.tsv", 4):
            target = find(row)
            if target is not None:
                target["audit"] = []
        orphans = collections.defaultdict(list)
        for row in _tsv(device_dir / "audit.tsv", 4):
            target = find(row[:3] + row[4:5])
            if target is not None:
                target["audit"] = (target["audit"] or []) + [row[3]]
            else:
                orphans[tuple(row[:3])].append(row[3])
        for (journey, pass_name, name), issues in orphans.items():
            screens.append(_screen(device, f"{journey}/audit:{name}", pass_name, "verify", None, audit=issues))
    return dedupe(screens)


def dedupe(screens):
    seen = collections.Counter()
    for screen in screens:
        seen[screen["key"]] += 1
        if seen[screen["key"]] > 1:
            screen["screen"] += f"#{seen[screen['key']]}"
            screen["key"] = f"{screen['device']}:{screen['screen']}@{screen['variant']}"
    return screens


# ---------------------------------------------------------------- deterministic scorer

def _lum(rgb):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _pixels(img):
    data = img.tobytes()
    return list(zip(data[0::3], data[1::3], data[2::3]))


def _modal(pixels):
    """The most common color after bucketing to 32 levels, and its share of the pixels."""
    counts = collections.Counter((r >> 3, g >> 3, b >> 3) for r, g, b in pixels)
    bucket, count = counts.most_common(1)[0]
    members = [p for p in pixels if (p[0] >> 3, p[1] >> 3, p[2] >> 3) == bucket]
    color = tuple(round(statistics.fmean(c)) for c in zip(*members))
    return color, count / len(pixels)


def pixel_facts(path, width=400):
    with Image.open(path) as opened:
        full_w, full_h = opened.size
        small = opened.convert("RGB").resize((width, max(1, round(width * full_h / full_w))), Image.Resampling.BOX)
    pixels = _pixels(small)
    bg, share = _modal(pixels)
    return {"full": (full_w, full_h), "size": small.size, "pixels": pixels, "bg": bg, "bg_share": share}


def _rows(facts):
    w, h = facts["size"]
    px = facts["pixels"]
    return [px[y * w:(y + 1) * w] for y in range(h)]


def _ink(pixel, bg):
    return abs(pixel[0] - bg[0]) + abs(pixel[1] - bg[1]) + abs(pixel[2] - bg[2]) > 60


def check_blank(facts):
    if facts["bg_share"] > 0.985:
        return f"blank capture: {facts['bg_share']:.1%} of the pixels are one color"
    return None


def check_theme(facts, variant):
    lum = _lum(facts["bg"])
    if variant == "light" and lum < 0.5:
        return f"light appearance requested but the background luminance is {lum:.2f}"
    if variant == "dark" and lum > 0.25:
        return f"dark appearance requested but the background luminance is {lum:.2f}"
    return None


def check_drawer_dim(facts):
    """iPhone drawer, light: the chat peeking beside the drawer must stay at page white (PLAN D19)."""
    w, h = facts["size"]
    rows = _rows(facts)[int(h * 0.1):int(h * 0.9)]
    strip = [p for row in rows for p in row[int(w * 0.89):w - 2]]
    if not strip:
        return None
    color, _share = _modal(strip)
    lum = _lum(color)
    score = 5 if lum >= 0.85 else (2 if lum >= 0.6 else 0)
    reason = None if score == 5 else (
        f"content beside the drawer is dimmed (luminance {lum:.2f}, page white is at least 0.85)")
    return score, reason, lum


def readable_width_pt(facts, scale):
    """90th percentile width in pt of the text rows between the toolbar and the composer, or None."""
    w, h = facts["size"]
    full_w = facts["full"][0]
    lo, hi = int(w * 0.015), int(w * 0.985)
    spans = []
    for row in _rows(facts)[int(h * 0.12):int(h * 0.88)]:
        xs = [x for x in range(lo, hi) if _ink(row[x], facts["bg"])]
        if not xs:
            continue
        span = xs[-1] - xs[0] + 1
        if len(xs) / span > 0.97:  # a solid bar or hairline, not text
            continue
        spans.append(span / w * full_w / scale)
    if not spans:
        return None
    spans.sort()
    return spans[min(len(spans) - 1, math.ceil(len(spans) * 0.9) - 1)]


def width_score(pt):
    return 5 if pt <= 780 else 4 if pt <= 900 else 2 if pt <= 1000 else 0


AUDIT_RULES = [
    ("tap_targets", re.compile(r"hit area|too small|target size", re.I)),
    ("contrast", re.compile(r"contrast", re.I)),
    ("hierarchy", re.compile(r"dynamic type|clipp|truncat|font size", re.I)),
]


def audit_scores(issues):
    """5 minus the count of findings per criterion. Hit area, contrast and labels are scored whenever the
    audit ran; text findings only lower the hierarchy score."""
    counts = collections.Counter()
    reasons = collections.defaultdict(list)
    for issue in issues:
        criterion = next((c for c, rule in AUDIT_RULES if rule.search(issue)), "semantics")
        counts[criterion] += 1
        reasons[criterion].append(issue)
    out = {}
    for criterion in ("tap_targets", "contrast", "semantics"):
        out[criterion] = (max(0, 5 - counts[criterion]), reasons[criterion])
    if counts["hierarchy"]:
        out["hierarchy"] = (max(0, 5 - counts["hierarchy"]), reasons["hierarchy"])
    return out


def native_hits(repo, files):
    total, per_file = 0, {}
    for name in files:
        path = Path(repo) / name
        if not path.exists():
            continue
        hits = sum(1 for line in path.read_text(errors="replace").splitlines() if NATIVE_PATTERN.search(line))
        per_file[name] = hits
        total += hits
    return total, per_file


def native_score(hits):
    return 5 if hits == 0 else 4 if hits <= 2 else 3 if hits <= 5 else 2 if hits <= 10 else 1 if hits <= 20 else 0


def deterministic(screen, owner, repo, criteria):
    """Returns {criterion: {"score": n, "reasons": [...]}} and a list of flags."""
    out, flags = {}, []

    def put(criterion, score, reasons):
        out[criterion] = {"score": score, "reasons": [r for r in reasons if r]}

    if screen.get("audit") is not None:
        for criterion, (score, reasons) in audit_scores(screen["audit"]).items():
            put(criterion, score, reasons)
    if owner["files"]:
        hits, per_file = native_hits(repo, owner["files"])
        if per_file:
            put("native", native_score(hits),
                [f"{hits} custom-UI hits in " + ", ".join(f"{f} ({n})" for f, n in per_file.items())] if hits else [])
    if screen["png"]:
        facts = pixel_facts(screen["png"])
        blank = check_blank(facts)
        if blank:
            flags.append("capture_failed")
            return {c: {"score": 0, "reasons": [blank]} for c in criteria}, flags
        theme = check_theme(facts, screen["variant"]) if screen["variant"] in ("light", "dark") else None
        if theme:
            put("contrast", 0, [theme] + out.get("contrast", {}).get("reasons", []))
        if screen["device"] == "iphone" and screen["variant"] == "light" and DRAWER_LIKE.search(screen["screen"]):
            checked = check_drawer_dim(facts)
            if checked and checked[1]:
                put("hierarchy", min(checked[0], out.get("hierarchy", {}).get("score", 5)),
                    [checked[1]] + out.get("hierarchy", {}).get("reasons", []))
        wide = screen["device"] in ("ipad-pro", "ipad-mini", "ipad", "mac")
        if wide and facts["full"][1] >= facts["full"][0] and CHAT_LIKE.search(screen["screen"]):
            pt = readable_width_pt(facts, SCALE.get(screen["device"], 2))
            if pt is not None:
                put("space", width_score(pt), [f"text rows span {pt:.0f} pt at the 90th percentile (readable width is about 720 pt)"]
                    if width_score(pt) < 5 else [])
    return out, flags


# ---------------------------------------------------------------- vision judge

def build_messages(rubric_text, criteria, meta, image_url, reverse=False):
    order = list(reversed(criteria)) if reverse else list(criteria)
    schema = {"scores": {c: "integer 0-5 or null" for c in order},
              "reasons": {c: "one sentence naming what you see" for c in order},
              "top_fix": "the single change that would raise the scores most, one sentence"}
    system = (
        "You are a strict iOS and macOS design reviewer. Score one screenshot of the AnyRouter app against the "
        "rubric below. Judge only what is visible. Do not reward effort; use the anchors.\n\n"
        "Return only JSON with this shape, criteria scored in this order:\n" + json.dumps(schema, indent=1) +
        "\n\n---\n" + rubric_text)
    user = [
        {"type": "text", "text": f"Device: {meta['device']}. Appearance or pass: {meta['variant']}. Screen: {meta['screen']}."},
        {"type": "image_url", "image_url": {"url": image_url}},
    ]
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def parse_judge(text, criteria):
    """Parses the judge's answer into {"scores": {c: float|None}, "reasons": {c: str}, "top_fix": str}."""
    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        raise ValueError("no JSON object in the judge answer")
    data = json.loads(match.group(0))
    scores, reasons = {}, {}
    for criterion in criteria:
        value = (data.get("scores") or {}).get(criterion)
        if value is None:
            scores[criterion] = None
        else:
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 5:
                raise ValueError(f"score for {criterion} is not 0 to 5: {value!r}")
            scores[criterion] = float(value)
        reasons[criterion] = str((data.get("reasons") or {}).get(criterion, ""))
    if all(v is None for v in scores.values()):
        raise ValueError("the judge scored nothing")
    return {"scores": scores, "reasons": reasons, "top_fix": str(data.get("top_fix", ""))}


def image_data_url(path, long_edge=1600):
    with Image.open(path) as img:
        img = img.convert("RGB")
        scale = long_edge / max(img.size)
        if scale < 1:
            img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
        buffer = io.BytesIO()
        img.save(buffer, "JPEG", quality=88)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode()


def http_transport(base, key):
    def call(payload):
        request = urllib.request.Request(
            base + "/chat/completions", data=json.dumps(payload).encode(),
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        last = None
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=180) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                last = f"HTTP {error.code}"
                if error.code not in (429, 500, 502, 503, 504):
                    raise RuntimeError(last + ": " + error.read().decode(errors="replace")[:300])
            except (urllib.error.URLError, TimeoutError) as error:
                last = str(error)
            time.sleep(2 ** attempt * 3)
        raise RuntimeError("judge request failed: " + str(last))
    return call


def resolve_model(requested, models_json):
    """The requested model when the catalog lists it with vision, else the first vision model."""
    data = (models_json or {}).get("data", [])
    vision = [m for m in data if "vision" in (m.get("capabilities") or [])]
    if any(m["id"] == requested for m in vision) or not vision:
        return requested
    return vision[0]["id"]


def fetch_models(base):
    try:
        with urllib.request.urlopen(base + "/models", timeout=30) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None


def judge_screen(screen, rubric_text, judged, model, transport, raw_log=None):
    url = image_data_url(screen["png"])
    runs = []
    for reverse in (False, True):
        payload = {"model": model, "temperature": 0, "max_tokens": 1500,
                   "response_format": {"type": "json_object"},
                   "messages": build_messages(rubric_text, judged, screen, url, reverse)}
        body = transport(payload)
        text = body["choices"][0]["message"]["content"]
        if raw_log is not None:
            raw_log.append({"key": screen["key"], "reverse": reverse, "model": model, "answer": text})
        runs.append(parse_judge(text, judged))
    return merge_runs(runs, judged, model)


def _mean_total(scores):
    values = [v for v in scores.values() if v is not None]
    return statistics.fmean(values) * 20 if values else None


def merge_runs(runs, criteria, model):
    merged = {}
    for criterion in criteria:
        values = [r["scores"].get(criterion) for r in runs if r["scores"].get(criterion) is not None]
        if values:
            merged[criterion] = {"score": statistics.fmean(values), "spread": max(values) - min(values),
                                 "runs": [r["scores"].get(criterion) for r in runs],
                                 "reason": next((r["reasons"].get(criterion) for r in runs if r["reasons"].get(criterion)), "")}
    totals = [_mean_total(r["scores"]) for r in runs]
    worst_run = min(runs, key=lambda r: _mean_total(r["scores"]) or 0)
    return {"model": model, "criteria": merged, "total_runs": totals,
            "spread": abs(totals[0] - totals[1]), "top_fix": worst_run["top_fix"]}


# ---------------------------------------------------------------- combining and reporting

def combine(det, judge, criteria):
    combined = {}
    for criterion in criteria:
        values = []
        if criterion in det:
            values.append(det[criterion]["score"])
        if judge and criterion in judge["criteria"]:
            values.append(judge["criteria"][criterion]["score"])
        if values:
            combined[criterion] = statistics.fmean(values)
    return combined


def total_of(criteria_scores):
    return round(_mean_total(criteria_scores), 1) if criteria_scores else None


def issues_of(det, judge):
    """Per criterion: the lowest score and its reason. Deterministic reasons win when they are the lower one."""
    found = {}
    for criterion, item in det.items():
        if item["score"] < 5 and item["reasons"]:
            found[criterion] = (item["score"], "; ".join(item["reasons"][:2]), "audit/pixels")
    if judge:
        for criterion, item in judge["criteria"].items():
            if item["score"] < 5 and item["reason"] and (criterion not in found or item["score"] < found[criterion][0]):
                found[criterion] = (item["score"], item["reason"], "judge")
    return found


def aggregate(screens, criteria):
    """One row per device and screen, averaged over light, dark and the other passes."""
    groups = collections.defaultdict(list)
    for screen in screens:
        groups[(screen["device"], screen["screen"])].append(screen)
    rows = {}
    for (device, name), members in groups.items():
        scored = [m for m in members if m["criteria"]]
        if not scored:
            continue
        per = {c: round(statistics.fmean(m["criteria"][c] for m in scored if c in m["criteria"]), 2)
               for c in criteria if any(c in m["criteria"] for m in scored)}
        issues = {}
        for member in scored:
            for criterion, (score, reason, source) in member["issues"].items():
                if criterion not in issues or score < issues[criterion]["score"]:
                    issues[criterion] = {"score": score, "reason": reason, "source": source, "variant": member["variant"]}
        spreads = [m["judge"]["spread"] for m in scored if m.get("judge")]
        rows[f"{device}:{name}"] = {
            "device": device, "screen": name, "variants": [m["variant"] for m in scored],
            "criteria": per, "total": total_of(per), "spread": round(statistics.fmean(spreads), 1) if spreads else 0.0,
            "owner": scored[0]["owner"], "issues": issues,
            "top_fix": next((m["judge"]["top_fix"] for m in scored if m.get("judge") and m["judge"]["top_fix"]), ""),
        }
    return rows


def delta_text(now, before, noise):
    if before is None or now is None:
        return "new"
    delta = now - before
    if abs(delta) < 0.05:
        return "="
    return f"{delta:+.1f}" + (" (noise)" if abs(delta) <= noise else "")


def worst_issues(rows, limit=5):
    candidates = []
    for key, row in rows.items():
        per_row = sorted(row["issues"].items(), key=lambda kv: kv[1]["score"])[:2]
        for criterion, issue in per_row:
            candidates.append({"screen": key, "criterion": criterion, "score": round(issue["score"], 2),
                               "variant": issue["variant"], "why": issue["reason"], "fix": row["top_fix"],
                               "lane": row["owner"]["lane"], "files": row["owner"]["files"]})
    candidates.sort(key=lambda c: (c["score"], c["screen"], c["criterion"]))
    return candidates[:limit]


def cell(text):
    return str(text).replace("|", "/").replace("\n", " ")[:220]


def render(result, previous):
    meta, rows = result["meta"], result["rows"]
    criteria = meta["criteria"]
    judge = meta["judge"]
    prev_rows = previous["rows"] if previous and previous.get("meta", {}).get("rubric_version") == meta["rubric_version"] else {}
    lines = ["# UX scorecard", "",
             f"Rubric v{meta['rubric_version']}, commit {meta.get('commit') or 'unknown'}"
             + (f", [source run]({meta['run_url']})" if meta.get("run_url") else "") + ".",
             f"Scored {meta['screens_scored']} screenshots in {len(rows)} screen rows. Judge: {judge['status']}"
             + (f" ({judge['model']}, {judge['judged']} judged, mean spread {judge['mean_spread']:.1f} points of 100)"
                if judge["judged"] else "") + "."]
    if previous and not prev_rows:
        lines.append("The previous run used another rubric version or has no rows, so there are no deltas.")
    elif not previous:
        lines.append("No previous run to compare with: every delta reads new.")
    lines += ["A delta no bigger than the judge spread is marked (noise). The total is the mean of the criteria that "
              "were scored (Scored column), so a total with few criteria says little.", ""]
    if meta["warnings"]:
        lines += [f"- Warning: {w}" for w in meta["warnings"]] + [""]
    if not rows:
        lines += ["Nothing to score: no screenshots were found in the inputs.", ""]
        return "\n".join(lines)

    lines += ["## By device", "", "| Device | Screens | Mean total | Criteria scored per screen | Delta |", "|---|---|---|---|---|"]
    for device in sorted({r["device"] for r in rows.values()}, key=lambda d: DEVICE_ORDER.index(d) if d in DEVICE_ORDER else 99):
        mine = {k: r for k, r in rows.items() if r["device"] == device and r["total"] is not None}
        before = {k: prev_rows[k] for k in mine if k in prev_rows and prev_rows[k]["total"] is not None}
        mean = statistics.fmean(r["total"] for r in mine.values()) if mine else None
        noise = statistics.fmean(r["spread"] for r in mine.values()) if mine else 0
        prev_mean = statistics.fmean(r["total"] for r in before.values()) if before else None
        same = statistics.fmean(mine[k]["total"] for k in before) if before else None
        covered = statistics.fmean(len(r["criteria"]) for r in mine.values()) if mine else 0
        lines.append(f"| {device} | {len(mine)} | {mean:.1f} | {covered:.1f} of {len(criteria)} | "
                     f"{delta_text(same, prev_mean, noise)} |")

    lines += ["", "## Screens", "", "| Screen | " + " | ".join(criteria) + " | Total | Scored | Delta |",
              "|---|" + "---|" * (len(criteria) + 3)]
    for key in sorted(rows, key=lambda k: (rows[k]["total"] if rows[k]["total"] is not None else 101, k)):
        row = rows[key]
        marks = " | ".join("" if c not in row["criteria"] else f"{row['criteria'][c]:.1f}" for c in criteria)
        before = prev_rows.get(key)
        noise = max(row["spread"], before["spread"] if before else 0)
        scored = f"{len(row['criteria'])}/{len(criteria)}"
        lines.append(f"| {key} | {marks} | {row['total']} | {scored} | "
                     f"{delta_text(row['total'], before['total'] if before else None, noise)} |")

    lines += ["", "## Five worst issues", "", "| # | Screen | Criterion | Score | Why | Fix | Owner |", "|---|---|---|---|---|---|---|"]
    for number, issue in enumerate(worst_issues(rows), 1):
        owner = issue["lane"] + (" (" + ", ".join(issue["files"][:2]) + ")" if issue["files"] else "")
        lines.append(f"| {number} | {issue['screen']} ({issue['variant']}) | {issue['criterion']} | {issue['score']} | "
                     f"{cell(issue['why'])} | {cell(issue['fix'] or '-')} | {cell(owner)} |")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------- main

def run(args, transport=None, models_json=None):
    version, criteria, judged, rubric_text = load_rubric()
    owners = load_owners()
    screens, warnings = [], []
    if args.screenshots and Path(args.screenshots).is_dir():
        screens += collect_screenshots(args.screenshots, args.device)
    if args.evidence and Path(args.evidence).is_dir():
        screens += collect_evidence(args.evidence, args.device)
    screens = dedupe(screens)

    for screen in screens:
        screen["owner"] = owner_of(owners, screen["screen"])
        try:
            det, screen["flags"] = deterministic(screen, screen["owner"], args.repo, criteria)
        except Exception as error:  # a broken PNG must not hide the others
            det, screen["flags"] = {}, ["error"]
            warnings.append(f"{screen['key']}: pixel checks failed: {error}")
        screen["det"], screen["judge"] = det, None

    key = os.environ.get("ANYROUTER_E2E_API_KEY", "")
    status, note, model = "skipped", "", args.model
    raw = []
    candidates = [s for s in screens if s["png"] and "capture_failed" not in s["flags"]]
    candidates.sort(key=lambda s: (DEVICE_ORDER.index(s["device"]) if s["device"] in DEVICE_ORDER else 99, s["key"]))
    if args.no_judge:
        note = "--no-judge"
    elif transport is None and not key:
        note = "ANYROUTER_E2E_API_KEY is not set"
    else:
        base = os.environ.get("UX_JUDGE_BASE", API_BASE)
        if transport is None:
            transport = http_transport(base, key)
            models_json = fetch_models(base)
        model = resolve_model(args.model, models_json)
        chosen = candidates[:args.max_judged]
        if len(candidates) > len(chosen):
            warnings.append(f"judged {len(chosen)} of {len(candidates)} screenshots (--max-judged)")

        def work(screen):
            try:
                screen["judge"] = judge_screen(screen, rubric_text, judged, model, transport, raw)
            except Exception as error:
                warnings.append(f"{screen['key']}: judge failed: {error}")
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(work, chosen))
        status = "ran"
    if status == "skipped":
        warnings.append(f"vision judge skipped: {note}. Only deterministic scores are shown.")

    for screen in screens:
        screen["criteria"] = combine(screen["det"], screen["judge"], criteria)
        screen["total"] = total_of(screen["criteria"])
        screen["issues"] = issues_of(screen["det"], screen["judge"])
    rows = aggregate(screens, criteria)
    judged_screens = [s for s in screens if s["judge"]]
    meta = {"rubric_version": version, "criteria": criteria,
            "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            "commit": args.commit, "run_url": args.run_url, "screens_scored": sum(1 for s in screens if s["criteria"]),
            "judge": {"status": status, "note": note, "model": model, "judged": len(judged_screens),
                      "mean_spread": statistics.fmean(s["judge"]["spread"] for s in judged_screens) if judged_screens else 0.0},
            "warnings": sorted(set(warnings))}
    result = {"meta": meta, "rows": rows, "worst": worst_issues(rows),
              "screens": {s["key"]: {k: s[k] for k in ("device", "screen", "variant", "source", "owner", "flags", "det",
                                                       "judge", "criteria", "total", "audit") if k in s}
                          for s in screens}}
    return result, raw


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--screenshots")
    parser.add_argument("--evidence")
    parser.add_argument("--out", default="ux-score.json")
    parser.add_argument("--summary", default="ux-score.md")
    parser.add_argument("--previous")
    parser.add_argument("--device", help="force the device tag (for example mac) for every input of this call")
    parser.add_argument("--no-judge", action="store_true")
    parser.add_argument("--max-judged", type=int, default=60)
    parser.add_argument("--model", default=os.environ.get("UX_JUDGE_MODEL", DEFAULT_MODEL))
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA", ""))
    parser.add_argument("--run-url", default="")
    parser.add_argument("--repo", default=str(ROOT))
    parser.add_argument("--raw-log", help="write the raw judge answers (jsonl) here")
    args = parser.parse_args(argv)
    if not args.screenshots and not args.evidence:
        parser.error("give --screenshots, --evidence or both")

    result, raw = run(args)
    previous = None
    if args.previous and Path(args.previous).exists():
        try:
            previous = json.loads(Path(args.previous).read_text())
        except ValueError:
            result["meta"]["warnings"].append("the previous ux-score.json could not be read")
    result["deltas"] = {k: delta_text(r["total"], previous["rows"][k]["total"], r["spread"])
                        for k, r in result["rows"].items() if previous and k in previous.get("rows", {})}
    Path(args.out).write_text(json.dumps(result, indent=1, default=list) + "\n")
    text = render(result, previous)
    Path(args.summary).write_text(text)
    if args.raw_log and raw:
        Path(args.raw_log).write_text("".join(json.dumps(r) + "\n" for r in raw))
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
