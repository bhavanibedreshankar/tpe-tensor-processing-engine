#!/usr/bin/env python3
"""
Parallel job-scheduler / regression runner -- the local, free/open-source
stand-in for a CI farm (Jenkins-replacement). Reads a testlist YAML
(verif/testlists/*.yaml), runs each entry's cocotb testcase via
`make -C verif/cocotb_tb/<dir> TESTCASE=<test>` (plus `TPE_SEED=<seed>` for
reproducible random-tier entries), parses cocotb's own per-directory JUnit
results.xml for pass/fail, and writes:
  - a per-test log under sim/logs/<suite>/
  - one aggregate JUnit XML at sim/logs/<suite>/regression.xml
  - a text summary table to stdout

Parallelism is across block directories (each is one already-built
Verilator sim binary reused via TESTCASE selection, see
docs/flows/build_flow.md); tests within the same directory run
sequentially, since two concurrent `make` invocations in the same
directory would race on that directory's shared sim_build/ and
results.xml. See docs/flows/regression_flow.md.

Exit code reflects *infrastructure* health, not a blanket pass/fail count:
0 unless a test ERRORed or TIMEOUT'd (crashed the harness itself). A test
FAIL against a catalogued bug (docs/verification/bug_list.md) is expected
and does not fail the run -- see docs/verification/test_plan.md section 5.
"""
import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
from tools.common.logger import get_logger  # noqa: E402

log = get_logger("regression")

DEFAULT_TIMEOUT_S = 120


def load_testlist(path: Path):
    with open(path) as f:
        data = yaml.safe_load(f)
    return data["suite"], data["tests"]


def _parse_results_xml(path: Path, test_name: str):
    """Returns (status, time_s) for `test_name` from a cocotb JUnit
    results.xml, or ("ERROR", None) if the file/testcase is missing."""
    if not path.exists():
        return "ERROR", None
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return "ERROR", None
    for tc in tree.getroot().iter("testcase"):
        if tc.get("name") == test_name:
            time_s = float(tc.get("time", 0.0))
            if tc.find("failure") is not None or tc.find("error") is not None:
                return "FAIL", time_s
            return "PASS", time_s
    return "ERROR", None


def run_one(entry: dict, log_dir: Path, timeout_s: int) -> dict:
    block_dir = REPO_ROOT / "verif" / "cocotb_tb" / entry["dir"]
    test_name = entry["test"]
    seed = entry.get("seed")

    tag = f"{entry['dir']}.{test_name}" + (f".seed{seed}" if seed is not None else "")
    log_file = log_dir / f"{tag}.log"

    env = os.environ.copy()
    env["TESTCASE"] = test_name
    if seed is not None:
        env["TPE_SEED"] = str(seed)

    start = time.time()
    timed_out = False
    stdout = ""
    try:
        proc = subprocess.run(
            ["make", "-C", str(block_dir)],
            env=env, capture_output=True, text=True, timeout=entry.get("timeout", timeout_s),
        )
        stdout = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        timed_out = True
        stdout = (e.stdout or "") + (e.stderr or "") + f"\n--- TIMEOUT after {timeout_s}s ---\n"
    wall_s = time.time() - start

    log_file.write_text(stdout)

    if timed_out:
        status, cocotb_time_s = "TIMEOUT", None
    else:
        status, cocotb_time_s = _parse_results_xml(block_dir / "results.xml", test_name)

    # Each test overwrites its directory's coverage.dat (one Verilator sim
    # binary, reused via TESTCASE selection -- see this file's header
    # comment), so it must be copied out under its own name immediately or
    # the next test run in the same directory clobbers it before
    # tools/cov_merge.py ever sees it.
    cov_src = block_dir / "coverage.dat"
    cov_dat = None
    if cov_src.exists():
        cov_dir = log_dir / "coverage"
        cov_dir.mkdir(parents=True, exist_ok=True)
        cov_dat = cov_dir / f"{tag}.dat"
        shutil.copy(cov_src, cov_dat)

    # Only verif/cocotb_tb/sram/ currently samples TB-side cocotb-coverage
    # (verif/cocotb_tb/sram/coverage.py), writing "<dir>_coverage.xml" in
    # its own directory -- same overwrite-per-test risk as coverage.dat
    # above, so copy it out too if present.
    tb_cov_src = block_dir / f"{entry['dir']}_coverage.xml"
    tb_cov_xml = None
    if tb_cov_src.exists():
        cov_dir = log_dir / "coverage"
        cov_dir.mkdir(parents=True, exist_ok=True)
        tb_cov_xml = cov_dir / f"{tag}.cocotb_coverage.xml"
        shutil.copy(tb_cov_src, tb_cov_xml)

    return {
        "tag": tag, "dir": entry["dir"], "test": test_name, "seed": seed,
        "status": status, "wall_s": wall_s, "cocotb_time_s": cocotb_time_s,
        "log": str(log_file.relative_to(REPO_ROOT)),
        "coverage_dat": str(cov_dat.relative_to(REPO_ROOT)) if cov_dat else None,
        "cocotb_coverage_xml": str(tb_cov_xml.relative_to(REPO_ROOT)) if tb_cov_xml else None,
    }


def run_group(entries: list, log_dir: Path, timeout_s: int) -> list:
    return [run_one(e, log_dir, timeout_s) for e in entries]


def write_junit(results: list, path: Path, suite: str):
    root = ET.Element("testsuite", name=suite, tests=str(len(results)),
                       failures=str(sum(r["status"] == "FAIL" for r in results)),
                       errors=str(sum(r["status"] in ("ERROR", "TIMEOUT") for r in results)))
    for r in results:
        tc = ET.SubElement(root, "testcase", classname=r["dir"], name=r["tag"],
                            time=str(r["wall_s"]))
        if r["status"] == "FAIL":
            ET.SubElement(tc, "failure", message=f"{r['tag']} failed (see {r['log']})")
        elif r["status"] in ("ERROR", "TIMEOUT"):
            ET.SubElement(tc, "error", message=f"{r['tag']} {r['status']} (see {r['log']})")
    ET.ElementTree(root).write(path, xml_declaration=True, encoding="unicode")


def print_summary(results: list, suite: str, elapsed_s: float):
    counts = defaultdict(int)
    for r in results:
        counts[r["status"]] += 1
    print()
    print(f"{'TAG':<55} {'STATUS':<8} {'WALL(s)':>8}")
    print("-" * 75)
    for r in sorted(results, key=lambda r: r["tag"]):
        print(f"{r['tag']:<55} {r['status']:<8} {r['wall_s']:>8.2f}")
    print("-" * 75)
    print(f"suite={suite} total={len(results)} "
          + " ".join(f"{k}={v}" for k, v in sorted(counts.items()))
          + f" wall={elapsed_s:.1f}s")
    if counts.get("FAIL"):
        print("\nFAILs are expected iff they match docs/verification/bug_list.md's "
              "'Caught by' column -- cross-check before treating a FAIL as a regression.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("suite", choices=["standalone", "sanity", "smoke", "daily", "random"])
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4,
                     help="max concurrent block directories (default: nproc)")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S,
                     help="per-test timeout in seconds (default: %(default)s)")
    args = ap.parse_args()

    testlist_path = REPO_ROOT / "verif" / "testlists" / f"{args.suite}.yaml"
    suite, entries = load_testlist(testlist_path)

    log_dir = REPO_ROOT / "sim" / "logs" / suite
    log_dir.mkdir(parents=True, exist_ok=True)

    groups = defaultdict(list)
    for e in entries:
        groups[e["dir"]].append(e)

    log.info(f"regression: suite={suite} tests={len(entries)} dirs={len(groups)} jobs={args.jobs}")

    start = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futures = {ex.submit(run_group, es, log_dir, args.timeout): d for d, es in groups.items()}
        for fut in concurrent.futures.as_completed(futures):
            d = futures[fut]
            try:
                results.extend(fut.result())
            except Exception as exc:
                log.error(f"regression: worker for dir={d} crashed: {exc}")
                results.append({"tag": f"{d}.<worker-crash>", "dir": d, "test": "?", "seed": None,
                                 "status": "ERROR", "wall_s": 0.0, "cocotb_time_s": None, "log": "",
                                 "coverage_dat": None, "cocotb_coverage_xml": None})
    elapsed = time.time() - start

    junit_path = log_dir / "regression.xml"
    write_junit(results, junit_path, suite)
    results_json_path = log_dir / "results.json"
    results_json_path.write_text(json.dumps({"suite": suite, "elapsed_s": elapsed, "results": results}, indent=2))
    print_summary(results, suite, elapsed)
    log.info(f"regression: JUnit written to {junit_path.relative_to(REPO_ROOT)}, "
             f"JSON to {results_json_path.relative_to(REPO_ROOT)} "
             "(consumed by tools/profiler.py and tools/cov_merge.py)")

    infra_broken = any(r["status"] in ("ERROR", "TIMEOUT") for r in results)
    sys.exit(1 if infra_broken else 0)


if __name__ == "__main__":
    main()
