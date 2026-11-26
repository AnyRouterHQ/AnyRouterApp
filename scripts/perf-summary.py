#!/usr/bin/env python3
"""Turns xcodebuild perf-test logs into a Markdown table and a JSON file.

Usage: perf-summary.py out.json log1 [log2 ...]   (one log per run)
Reads lines like:
  Test Case '-[AnyRouterUITests.PerformanceTests testColdLaunch]' measured [Duration (AppLaunch), s] average: 1.2,
  relative standard deviation: 4.5%, values: [...]
The average is recomputed from values (6 decimals) and RSD is the sample deviation of the values.
Prints Markdown to stdout. Baseline only: it never fails on the numbers.
"""
import json
import re
import statistics
import sys

LINE = re.compile(
    r"Test Case '-\[\S+\.(\w+) (\w+)\]' measured \[(.+), ([^,\]]+)\] average: ([-\d.eE+]+), "
    r"relative standard deviation: ([-\d.eE+]+)%, values: \[([^\]]*)\]"
)


def parse(path):
    rows = {}
    with open(path, errors="replace") as handle:
        for line in handle:
            match = LINE.search(line)
            if match:
                _cls, test, metric, unit, _average, rsd, raw = match.groups()
                # The printed average has 3 decimals, which hides microsecond signposts; use the raw values.
                values = [float(v) for v in raw.split(",") if v.strip()]
                if values:
                    mean = statistics.fmean(values)
                    spread = statistics.stdev(values) / abs(mean) * 100 if mean and len(values) > 1 else 0.0
                    rows[(test, metric, unit)] = (mean, spread)
                else:
                    rows[(test, metric, unit)] = (float(_average), float(rsd))
    return rows


def main():
    out, logs = sys.argv[1], sys.argv[2:]
    runs = [parse(log) for log in logs]
    keys = sorted({key for run in runs for key in run})
    result = []
    print("| Test | Metric | Unit | Run averages | Run RSD % | Mean of runs | Spread across runs % |")
    print("|---|---|---|---|---|---|---|")
    for key in keys:
        values = [run[key] for run in runs if key in run]
        averages = [v[0] for v in values]
        mean = statistics.fmean(averages)
        spread = (max(averages) - min(averages)) / abs(mean) * 100 if mean else 0.0
        result.append({
            "test": key[0], "metric": key[1], "unit": key[2], "averages": averages,
            "rsd_percent": [v[1] for v in values], "mean": mean, "spread_percent": spread,
        })
        print(f"| {key[0]} | {key[1]} | {key[2]} | {', '.join(f'{a:.4g}' for a in averages)} | "
              f"{', '.join(f'{v[1]:.1f}' for v in values)} | {mean:.4g} | {spread:.1f} |")
    if not keys:
        print("| (no measured lines found, see the raw logs artifact) | | | | | | |")
    with open(out, "w") as handle:
        json.dump(result, handle, indent=2)


main()
