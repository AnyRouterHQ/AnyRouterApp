#!/usr/bin/env python3
"""Build journeys.md from an evidence folder: python3 journeys-report.py <evidence-dir> > journeys.md

Reads, per device folder: results.tsv (journey, pass, step number, step name, png),
audit.tsv (journey, pass, step, issue) and ../summary-<device>.json (xcresulttool test summary).
"""
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path


def rows(path):
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return [r for r in csv.reader(handle, delimiter="\t") if r]


def main(root: Path) -> None:
    print("# Journey evidence\n")
    devices = sorted(p for p in root.iterdir() if p.is_dir())
    if not devices:
        print("No device folders found. The run produced no evidence; read the run log.")
        return
    for device in devices:
        print(f"## {device.name}\n")
        summary_path = root / f"summary-{device.name}.json"
        if summary_path.exists():
            summary = json.loads(summary_path.read_text())
            print(f"Result: **{summary.get('result', 'unknown')}**, "
                  f"passed {summary.get('passedTests', '?')}, failed {summary.get('failedTests', '?')}, "
                  f"total {summary.get('totalTestCount', '?')}\n")
            for failure in summary.get("testFailures", []):
                print(f"- FAILED {failure.get('testName', '?')}: {failure.get('failureText', '')}")
            print()
        else:
            print("No xcresult summary for this device.\n")
        steps = defaultdict(int)
        for journey, _pass, _n, _name, _png in rows(device / "results.tsv"):
            steps[(journey, _pass)] += 1
        issues = defaultdict(int)
        for row in rows(device / "audit.tsv"):
            issues[(row[0], row[1])] += 1
        print("| Journey | Pass | Steps | Audit findings |")
        print("|---|---|---|---|")
        for (journey, pass_name), count in sorted(steps.items()):
            print(f"| {journey} | {pass_name} | {count} | {issues[(journey, pass_name)]} |")
        print("\nScreenshots:\n")
        for journey, pass_name, number, name, png in rows(device / "results.tsv"):
            print(f"- {device.name}/{png}")
        audit = rows(device / "audit.tsv")
        if audit:
            print("\nAccessibility audit findings:\n")
            for journey, pass_name, step, issue in audit:
                print(f"- {journey} / {pass_name} / {step}: {issue}")
        print()


if __name__ == "__main__":
    main(Path(sys.argv[1]))
