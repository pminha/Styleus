#!/usr/bin/env python3
"""Summarize the opt-in Mac scroll test CSV; never reads application content."""
import argparse
import csv
import statistics
import tempfile
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("path", nargs="?", type=Path,
                    default=Path(tempfile.gettempdir()) / "styleus-scroll-diagnostics.csv")
args = parser.parse_args()
if not args.path.exists():
    parser.exit(1, "No saved scroll test yet. Stop Recording in the test window first.\n")
with args.path.open(newline="") as handle:
    rows = list(csv.DictReader(handle))


def number(row, key):
    return float(row.get(key) or 0)


def percentile(values, fraction):
    if not values:
        return 0.0
    return sorted(values)[round((len(values) - 1) * fraction)]


print("Report:", args.path)
print("Rows by stage:", dict(Counter(row["kind"] for row in rows)))
posted = {row["tag"]: row for row in rows if row["kind"] == "posted"}
received = [row for row in rows if row["kind"] == "app-received"]
paired = [(posted[row["tag"]], row) for row in received if row["tag"] in posted]
print("Styleus posted/delivered matches:", len(paired), "/", len(posted))
print("Counts can differ because macOS coalesces adjacent scroll events; per-tag differences alone do not prove lost input.")
for label, events in [("Posted", list(posted.values())), ("Delivered", [after for _, after in paired])]:
    print(label, "signed point totals:",
          {axis: round(sum(number(row, axis) for row in events), 6) for axis in ["dx", "dy"]},
          "absolute vertical total:", round(sum(abs(number(row, "dy")) for row in events), 6))
for field in ["precise", "dx", "dy", "phase", "momentum", "line_x", "line_y", "fixed_x", "fixed_y", "point_x", "point_y"]:
    changes = [(before[field], after[field]) for before, after in paired
               if abs(number(before, field) - number(after, field)) > 0.00001]
    if changes:
        print("Per-tag difference (may include coalescing)", field, "count", len(changes), "examples", changes[:12])
delays = [(number(after, "time") - number(before, "time")) * 1000 for before, after in paired]
if delays:
    print("Post-to-own-window delay ms: median=%.2f p95=%.2f max=%.2f" %
          (statistics.median(delays), percentile(delays, 0.95), max(delays)))

groups = {
    "Styleus input": [row for row in rows if row["kind"] == "input"],
    "Styleus delivered": [after for _, after in paired],
    "Unmatched/native delivered": [row for row in received if row["tag"] not in posted],
    "Web wheel": [row for row in rows if row["kind"] == "web-wheel"],
    "Web content movement": [row for row in rows if row["kind"] == "web-scroll"],
}
for label, events in groups.items():
    if not events:
        continue
    # Gaps between separate gestures are excluded, but within-gesture stalls remain.
    times = [number(row, "time") for row in events]
    gaps = [(b - a) * 1000 for a, b in zip(times, times[1:]) if 0 < b - a < 0.5]
    magnitudes = [abs(number(row, "dy")) for row in events if number(row, "dy") != 0]
    print(label, "count", len(events), "precise", dict(Counter(row["precise"] for row in events)))
    if gaps:
        print("  interval ms: median=%.2f p95=%.2f max=%.2f" %
              (statistics.median(gaps), percentile(gaps, 0.95), max(gaps)))
    if magnitudes:
        print("  nonzero vertical magnitude: min=%.3f median=%.3f max=%.3f" %
              (min(magnitudes), statistics.median(magnitudes), max(magnitudes)))
        print("  frequent magnitudes:", Counter(round(value, 3) for value in magnitudes).most_common(10))
