#!/usr/bin/env python3
"""
Merges the per-test coverage files a regression run left under
sim/logs/<suite>/coverage/ (see tools/regression.py, which copies each
test's coverage.dat / *_coverage.xml out under its own name before the
next test in the same directory overwrites them):

- Verilator `coverage.dat` (structural line/toggle/branch plus every
  RTL-side SV covergroup, since --coverage-user writes into the same
  file, see docs/verification/coverage_plan.md section 1) -- merged with
  `verilator_coverage -write`, summarized with
  `verilator_coverage --report summary,hier`.
- cocotb-coverage `*.cocotb_coverage.xml` (TB-side CoverPoint/CoverCross;
  only verif/cocotb_tb/sram/coverage.py samples any today) -- summed
  bin-by-bin across every file sharing the same covergroup shape (they do,
  since they all come from that one coverage.py module) into one XML with
  the same structure, hit counts added and cover_percentage/coverage
  recomputed at every level.

Usage: python3 tools/cov_merge.py <suite>   (suite = smoke/daily/random/...)
"""
import argparse
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
from tools.common.logger import get_logger  # noqa: E402

log = get_logger("cov_merge")


def merge_verilator(cov_dir: Path, annotate: bool):
    dat_files = sorted(cov_dir.glob("*.dat"))
    if not dat_files:
        log.warning(f"cov_merge: no coverage.dat files under {cov_dir}")
        return

    merged_path = cov_dir.parent / "merged_coverage.dat"
    log.info(f"cov_merge: merging {len(dat_files)} coverage.dat files -> {merged_path}")
    subprocess.run(
        ["verilator_coverage", "-write", str(merged_path)] + [str(p) for p in dat_files],
        check=True,
    )

    summary_path = cov_dir.parent / "coverage_summary.txt"
    proc = subprocess.run(
        ["verilator_coverage", "--report", "summary,hier", str(merged_path)],
        capture_output=True, text=True, check=True,
    )
    summary_path.write_text(proc.stdout)
    print(proc.stdout)
    log.info(f"cov_merge: summary written to {summary_path.relative_to(REPO_ROOT)}")

    if annotate:
        annotate_dir = cov_dir.parent / "coverage_annotated"
        subprocess.run(
            ["verilator_coverage", "--annotate", str(annotate_dir), str(merged_path)],
            check=True,
        )
        log.info(f"cov_merge: annotated source written under {annotate_dir.relative_to(REPO_ROOT)}")


def _sum_bins(dst: ET.Element, src: ET.Element):
    """Recursively adds src's `hits` into dst's, matched by `abs_name`
    (assumes identical tree shape, true for every cocotb-coverage export
    this repo produces -- one shared covergroup module per block).
    Recomputes coverage/cover_percentage bottom-up after hits are summed."""
    dst_children = {c.get("abs_name"): c for c in dst}
    for src_child in src:
        dst_child = dst_children.get(src_child.get("abs_name"))
        if dst_child is None:
            continue  # shape mismatch -- skip rather than guess
        if src_child.tag.startswith("bin"):
            dst_child.set("hits", str(int(dst_child.get("hits", 0)) + int(src_child.get("hits", 0))))
        else:
            _sum_bins(dst_child, src_child)


def _recompute_coverage(el: ET.Element) -> tuple:
    """Bottom-up: a bin is 'covered' if hits > 0 (at_least=1 default,
    matching every bin in this repo's coverpoints); a coverpoint/group's
    coverage is how many of its children are covered."""
    if el.tag.startswith("bin"):
        covered = int(el.get("hits", 0)) > 0
        return 1, int(covered)
    total = covered = 0
    for child in el:
        t, c = _recompute_coverage(child)
        total += t
        covered += c
    el.set("size", str(total))
    el.set("coverage", str(covered))
    el.set("cover_percentage", f"{(100.0 * covered / total) if total else 0.0:.2f}")
    return total, covered


def merge_cocotb_coverage(cov_dir: Path):
    xml_files = sorted(cov_dir.glob("*.cocotb_coverage.xml"))
    if not xml_files:
        log.info(f"cov_merge: no *.cocotb_coverage.xml files under {cov_dir} (nothing to merge)")
        return

    merged = ET.parse(xml_files[0]).getroot()
    for f in xml_files[1:]:
        _sum_bins(merged, ET.parse(f).getroot())
    _recompute_coverage(merged)

    merged_path = cov_dir.parent / "cocotb_coverage_merged.xml"
    ET.ElementTree(merged).write(merged_path, xml_declaration=True, encoding="unicode")
    log.info(f"cov_merge: merged {len(xml_files)} cocotb-coverage file(s) -> "
             f"{merged_path.relative_to(REPO_ROOT)} ({merged.get('cover_percentage')}% overall)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("suite")
    ap.add_argument("--annotate", action="store_true",
                     help="also write a per-source annotated report (verilator_coverage --annotate)")
    args = ap.parse_args()

    cov_dir = REPO_ROOT / "sim" / "logs" / args.suite / "coverage"
    if not cov_dir.exists():
        log.error(f"cov_merge: {cov_dir} not found -- run "
                  f"`python3 tools/regression.py {args.suite}` first")
        sys.exit(1)

    merge_verilator(cov_dir, args.annotate)
    merge_cocotb_coverage(cov_dir)


if __name__ == "__main__":
    main()
