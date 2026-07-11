#!/usr/bin/env python3
"""
Per-test wall-clock profiling over a regression run's results.json (see
tools/regression.py). Reports the slowest tests and flags outliers -- any
test whose wall time exceeds `--outlier-factor` (default 3x) times that
directory's own median, since comparing across directories isn't
meaningful (matrix_engine/dma naturally run slower per-test than pmu/debug
regardless of anything being wrong).

Usage: python3 tools/profiler.py <suite>
"""
import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("suite")
    ap.add_argument("--top", type=int, default=10, help="how many slowest tests to list (default: %(default)s)")
    ap.add_argument("--outlier-factor", type=float, default=3.0,
                     help="flag a test as an outlier if wall_s > factor * its directory's median (default: %(default)s)")
    args = ap.parse_args()

    results_path = REPO_ROOT / "sim" / "logs" / args.suite / "results.json"
    if not results_path.exists():
        print(f"profiler: {results_path} not found -- run `python3 tools/regression.py {args.suite}` first",
              file=sys.stderr)
        sys.exit(1)

    data = json.loads(results_path.read_text())
    results = data["results"]

    by_dir = defaultdict(list)
    for r in results:
        by_dir[r["dir"]].append(r)

    print(f"suite={data['suite']} total_wall_s={data['elapsed_s']:.1f} tests={len(results)}")
    print()
    print(f"Slowest {args.top} tests overall:")
    for r in sorted(results, key=lambda r: -r["wall_s"])[: args.top]:
        print(f"  {r['wall_s']:>8.2f}s  {r['tag']}")

    print()
    print("Per-directory median wall time:")
    medians = {}
    for d, rs in sorted(by_dir.items()):
        med = statistics.median(r["wall_s"] for r in rs)
        medians[d] = med
        print(f"  {d:<20} n={len(rs):<4} median={med:>7.2f}s")

    outliers = [
        r for r in results
        if medians[r["dir"]] > 0 and r["wall_s"] > args.outlier_factor * medians[r["dir"]]
    ]
    print()
    if outliers:
        print(f"Outliers (> {args.outlier_factor}x their directory's median):")
        for r in sorted(outliers, key=lambda r: -r["wall_s"]):
            print(f"  {r['wall_s']:>8.2f}s  {r['tag']}  (dir median {medians[r['dir']]:.2f}s)")
    else:
        print("No outliers.")


if __name__ == "__main__":
    main()
