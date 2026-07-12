#!/usr/bin/env python3
"""
run_sim -- single entry point for running TPE cocotb tests without
littering the source tree with generated files. `make -C
verif/cocotb_tb/<dir> TESTCASE=<test>` writes sim_build/, results.xml,
dump.vcd, coverage.dat, <block>_scoreboard_work/ and __pycache__ straight
into that source directory (see docs/flows/build_flow.md) -- this wrapper
redirects everything it can (SIM_BUILD/COCOTB_RESULTS_FILE/trace-file/
coverage-file are all make-variable overrides the per-block Makefiles
already respect) and sweeps up the handful of artifacts that can't be
redirected (scoreboard.py/coverage.py hardcode relative `Path("...")`
names), so verif/cocotb_tb/<dir> is byte-for-byte clean before and after
every run.

Resolves a bare test name to its block directory from
verif/testlists/standalone.yaml (the master catalog) automatically --
no need to know or type `-C verif/cocotb_tb/<dir>` yourself. Every
generated file for a run lands under one place:

    $WORK_DIR/<work-dir-name, default "WORK">/<tag>/         (--test)
    $WORK_DIR/<work-dir-name>/<suite>/<tag>/                 (--suite)

where <tag> is "<dir>.<test>" (plus ".seed<N>" when seeded). WORK_DIR
comes from `source env.sh` (falls back to sim/logs/adhoc if unset, same
default env.sh uses).

This sits alongside the existing Makefile / tools/regression.py /
tools/cov_merge.py / tools/lint.py / tools/waves.py flow -- none of that
changes or is required; see docs/HANDBOOK.md.

Examples:
    run_sim --test dma_sanity_test
    run_sim --test dma_random_test --seed 12345 --coverage --waves
    run_sim --suite smoke --jobs 8 --coverage
    run_sim --suite daily --farm
    run_sim --lint --block tpe_dma
    run_sim --clean --suite smoke
    run_sim --list
"""
import argparse
import concurrent.futures
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
from tools.cov_merge import merge_cocotb_coverage, merge_verilator  # noqa: E402
from tools.regression import _parse_results_xml as parse_results_xml  # noqa: E402

log = get_logger("run_sim")

DEFAULT_TIMEOUT_S = 120
TESTLIST_DIR = REPO_ROOT / "verif" / "testlists"
VENV = REPO_ROOT / ".venv"
SUITES = ["standalone", "sanity", "smoke", "daily", "random"]


def work_root(args) -> Path:
    work_dir = Path(os.environ.get("WORK_DIR", REPO_ROOT / "sim" / "logs" / "adhoc"))
    return work_dir / args.work_dir_name


def load_catalog() -> dict:
    with open(TESTLIST_DIR / "standalone.yaml") as f:
        data = yaml.safe_load(f)
    by_name = {}
    for e in data["tests"]:
        by_name.setdefault(e["test"], e)
    return by_name


def load_testlist(suite: str) -> list:
    with open(TESTLIST_DIR / f"{suite}.yaml") as f:
        return yaml.safe_load(f)["tests"]


def venv_env(extra: dict) -> dict:
    if not (VENV / "bin" / "activate").exists():
        log.error(f"run_sim: {VENV} not found -- run `make venv` first")
        sys.exit(1)
    env = os.environ.copy()
    env["VIRTUAL_ENV"] = str(VENV)
    env["PATH"] = f"{VENV / 'bin'}:{env.get('PATH', '')}"
    env.update(extra)
    return env


def tag_for(dir_: str, test: str, seed) -> str:
    return f"{dir_}.{test}" + (f".seed{seed}" if seed is not None else "")


def sweep_generated(block_dir: Path, result_dir: Path, cov_root: Path, tag: str, keep_coverage: bool):
    """Moves/copies the artifacts a test writes at hardcoded relative
    paths inside block_dir -- can't be redirected via make/env vars, see
    scoreboard.py's `Path("<block>_scoreboard_work")` and sram's
    `Path("sram_coverage.xml")` -- into result_dir/cov_root, then removes
    them from the source tree so it's clean again. The TB-side coverage
    XML is only kept (copied into cov_root) when `-coverage` was actually
    requested; otherwise it's discarded, same as coverage.dat below."""
    for p in sorted(block_dir.glob("*_scoreboard_work")):
        dest = result_dir / p.name
        if dest.exists():
            shutil.rmtree(dest)
        shutil.move(str(p), str(dest))
    for p in sorted(block_dir.glob("*_coverage.xml")):
        if keep_coverage:
            cov_root.mkdir(parents=True, exist_ok=True)
            shutil.copy(p, cov_root / f"{tag}.cocotb_coverage.xml")
        p.unlink()
    pycache = block_dir / "__pycache__"
    if pycache.exists():
        shutil.rmtree(pycache)


def run_one(dir_: str, test: str, seed, result_dir: Path, timeout_s: int,
            cov_root: Path = None, keep_coverage: bool = False, keep_waves: bool = False) -> dict:
    block_dir = REPO_ROOT / "verif" / "cocotb_tb" / dir_
    tag = tag_for(dir_, test, seed)
    result_dir.mkdir(parents=True, exist_ok=True)
    cov_root = cov_root or (result_dir / "coverage")

    results_xml = result_dir / "results.xml"
    log_file = result_dir / "run.log"
    # Every block Makefile hardcodes --coverage-line/-toggle/-user and
    # --trace/--trace-structs (see docs/flows/build_flow.md section 4), so
    # Verilator always instruments coverage and always traces regardless of
    # -coverage/-waves -- run_sim can only choose where each file lands, not
    # whether it's produced. Without the matching flag, tuck it inside
    # sim_build (an already-expected build-scratch dir) so nothing shows up
    # in result_dir unless actually asked for.
    coverage_dat = (result_dir / "coverage.dat") if keep_coverage \
        else (result_dir / "sim_build" / "coverage.dat")
    dump_vcd = (result_dir / "dump.vcd") if keep_waves \
        else (result_dir / "sim_build" / "dump.vcd")

    # Passed as `make VAR=value` command-line overrides, not env vars: every
    # block Makefile sets `SIM_BUILD := sim_build` (a hard assignment, see
    # verif/cocotb_tb/*/Makefile), which clobbers an env-var override since
    # `:=` doesn't defer to the environment the way cocotb's own `?=`
    # default does. Command-line overrides beat any in-Makefile assignment
    # regardless of `:=`/`=`/`?=`, so use those uniformly here.
    make_vars = [
        f"TESTCASE={test}",
        f"SIM_BUILD={result_dir / 'sim_build'}",
        f"COCOTB_RESULTS_FILE={results_xml}",
        f"SIM_ARGS=--trace-file {dump_vcd}",
        f"PLUSARGS=+verilator+coverage+file+{coverage_dat}",
    ]
    if seed is not None:
        make_vars.append(f"TPE_SEED={seed}")
    env = venv_env({})

    start = time.time()
    timed_out = False
    try:
        proc = subprocess.run(["make", "-C", str(block_dir)] + make_vars, env=env,
                               capture_output=True, text=True, timeout=timeout_s)
        stdout = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        timed_out = True
        stdout = (e.stdout or "") + (e.stderr or "") + f"\n--- TIMEOUT after {timeout_s}s ---\n"
    wall_s = time.time() - start
    log_file.write_text(stdout)

    sweep_generated(block_dir, result_dir, cov_root, tag, keep_coverage)

    if keep_coverage and coverage_dat.exists():
        cov_root.mkdir(parents=True, exist_ok=True)
        shutil.copy(coverage_dat, cov_root / f"{tag}.dat")

    if timed_out:
        status, cocotb_time_s = "TIMEOUT", None
    else:
        status, cocotb_time_s = parse_results_xml(results_xml, test)

    return {
        "tag": tag, "dir": dir_, "test": test, "seed": seed, "status": status,
        "wall_s": wall_s, "cocotb_time_s": cocotb_time_s,
        "result_dir": result_dir, "log": log_file, "dump_vcd": dump_vcd,
    }


def run_group(entries: list, suite_root: Path, timeout_s: int, keep_coverage: bool) -> list:
    cov_root = suite_root / "coverage"
    out = []
    for e in entries:
        seed = e.get("seed")
        tag = tag_for(e["dir"], e["test"], seed)
        out.append(run_one(e["dir"], e["test"], seed, suite_root / tag, timeout_s,
                            cov_root=cov_root, keep_coverage=keep_coverage))
    return out


def write_junit(results: list, path: Path, suite: str):
    root = ET.Element("testsuite", name=suite, tests=str(len(results)),
                       failures=str(sum(r["status"] == "FAIL" for r in results)),
                       errors=str(sum(r["status"] in ("ERROR", "TIMEOUT") for r in results)))
    for r in results:
        tc = ET.SubElement(root, "testcase", classname=r["dir"], name=r["tag"], time=str(r["wall_s"]))
        if r["status"] == "FAIL":
            ET.SubElement(tc, "failure", message=f"{r['tag']} failed (see {r['log']})")
        elif r["status"] in ("ERROR", "TIMEOUT"):
            ET.SubElement(tc, "error", message=f"{r['tag']} {r['status']} (see {r['log']})")
    path.parent.mkdir(parents=True, exist_ok=True)
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


def report_coverage(cov_dir: Path, annotate: bool):
    if not cov_dir.exists():
        log.warning(f"run_sim: no coverage under {cov_dir}, nothing to merge")
        return
    merge_verilator(cov_dir, annotate)
    merge_cocotb_coverage(cov_dir)


def open_waves(dump_vcd: Path):
    if not dump_vcd.exists():
        log.warning(f"run_sim: no waveform at {dump_vcd} (did tracing run?)")
        return
    gtkwave = shutil.which("gtkwave")
    if not gtkwave:
        log.error("run_sim: gtkwave not found on PATH")
        return
    subprocess.Popen([gtkwave, str(dump_vcd)])
    log.info(f"run_sim: launched gtkwave on {dump_vcd}")


def run_single_test(args) -> int:
    catalog = load_catalog()
    entry = catalog.get(args.test)
    if entry is None:
        log.error(f"run_sim: unknown test {args.test!r} -- not in "
                  f"verif/testlists/standalone.yaml, try --list")
        return 2

    result_dir = work_root(args) / tag_for(entry["dir"], args.test, args.seed)
    log.info(f"run_sim: test={args.test} dir={entry['dir']} kind={entry.get('kind')}"
             + (f" seed={args.seed}" if args.seed is not None else "")
             + f" -> {result_dir}")

    r = run_one(entry["dir"], args.test, args.seed, result_dir, args.timeout,
                keep_coverage=args.coverage, keep_waves=args.waves)
    print(f"\n{r['tag']:<50} {r['status']:<8} {r['wall_s']:>8.2f}s")
    print(f"log: {r['log']}")
    if entry.get("expect_fail") and r["status"] == "FAIL":
        print(f"note: FAIL expected -- see docs/verification/bug_list.md ({entry['expect_fail']})")

    if args.coverage:
        report_coverage(result_dir / "coverage", args.annotate)
    if args.waves:
        open_waves(r["dump_vcd"])

    return 0 if r["status"] == "PASS" else 1


def run_suite(args) -> int:
    entries = load_testlist(args.suite)
    suite_root = work_root(args) / args.suite

    groups = defaultdict(list)
    for e in entries:
        groups[e["dir"]].append(e)

    log.info(f"run_sim: suite={args.suite} tests={len(entries)} dirs={len(groups)} "
             f"jobs={args.jobs} -> {suite_root}")

    start = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futures = {ex.submit(run_group, es, suite_root, args.timeout, args.coverage): d
                   for d, es in groups.items()}
        for fut in concurrent.futures.as_completed(futures):
            d = futures[fut]
            try:
                results.extend(fut.result())
            except Exception as exc:
                log.error(f"run_sim: worker for dir={d} crashed: {exc}")
                results.append({"tag": f"{d}.<worker-crash>", "dir": d, "test": "?", "seed": None,
                                 "status": "ERROR", "wall_s": 0.0, "cocotb_time_s": None,
                                 "result_dir": suite_root, "log": "", "dump_vcd": None})
    elapsed = time.time() - start

    junit_path = suite_root / "regression.xml"
    write_junit(results, junit_path, args.suite)
    print_summary(results, args.suite, elapsed)
    log.info(f"run_sim: JUnit written to {junit_path}")

    if args.coverage:
        report_coverage(suite_root / "coverage", args.annotate)

    infra_broken = any(r["status"] in ("ERROR", "TIMEOUT") for r in results)
    return 1 if infra_broken else 0


def do_lint(args) -> int:
    cmd = [sys.executable, str(REPO_ROOT / "tools" / "lint.py")]
    if args.block:
        cmd += ["--block", args.block]
    return subprocess.run(cmd).returncode


def do_list(args) -> int:
    catalog = load_catalog()
    print(f"{'TEST':<34} {'DIR':<16} {'KIND':<10} EXPECT_FAIL")
    for name, e in sorted(catalog.items()):
        print(f"{name:<34} {e['dir']:<16} {e.get('kind', ''):<10} {e.get('expect_fail', '')}")
    print(f"\n{len(catalog)} tests total. Suites: {', '.join(SUITES)} "
          f"(verif/testlists/*.yaml).")
    return 0


def do_clean(args) -> int:
    root = work_root(args)

    def rm(p: Path):
        if p.exists():
            shutil.rmtree(p)
            log.info(f"run_sim: removed {p}")
        else:
            log.warning(f"run_sim: {p} does not exist, nothing to clean")

    if args.suite:
        rm(root / args.suite)
        return 0
    if args.test:
        catalog = load_catalog()
        entry = catalog.get(args.test)
        prefix = f"{entry['dir']}.{args.test}" if entry else args.test
        matches = sorted(root.glob(f"{prefix}*")) if root.exists() else []
        if not matches:
            log.warning(f"run_sim: nothing under {root} matches {args.test!r}")
        for p in matches:
            rm(p)
        return 0
    rm(root)
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="run_sim", description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-test", "--test", dest="test", metavar="NAME",
                     help="run one test by name, auto-resolving its block dir from "
                          "verif/testlists/standalone.yaml")
    ap.add_argument("-suite", "--suite", dest="suite", choices=SUITES,
                     help="run every test in verif/testlists/<suite>.yaml")
    ap.add_argument("-seed", "--seed", dest="seed", type=int, default=None,
                     help="TPE_SEED override, only used with --test (suite entries carry their own seed)")
    ap.add_argument("-jobs", "--jobs", dest="jobs", type=int, default=os.cpu_count() or 4,
                     help="max concurrent block directories for --suite (default: nproc)")
    ap.add_argument("-timeout", "--timeout", dest="timeout", type=int, default=DEFAULT_TIMEOUT_S,
                     help="per-test timeout in seconds (default: %(default)s)")
    ap.add_argument("-farm", "--farm", dest="farm", action="store_true",
                     help="run via the local parallel job runner (alias for now -- "
                          "no remote scheduler wired up, see docs/HANDBOOK.md)")
    ap.add_argument("-coverage", "--coverage", dest="coverage", action="store_true",
                     help="merge+report coverage for this run (single test or suite) via tools/cov_merge.py")
    ap.add_argument("-annotate", "--annotate", dest="annotate", action="store_true",
                     help="with --coverage, also write a per-source annotated report")
    ap.add_argument("-lint", "--lint", dest="lint", action="store_true",
                     help="run tools/lint.py (verilator --lint-only across rtl/)")
    ap.add_argument("-block", "--block", dest="block", metavar="NAME",
                     help="with --lint, lint only this block")
    ap.add_argument("-waves", "--waves", dest="waves", action="store_true",
                     help="open GTKWave on the run's dump.vcd afterward (requires --test)")
    ap.add_argument("-clean", "--clean", dest="clean", action="store_true",
                     help="remove work dirs under WORK_DIR/<work-dir-name> "
                          "(scope with --test/--suite, or everything if neither given)")
    ap.add_argument("-list", "--list", dest="list_tests", action="store_true",
                     help="list every test in verif/testlists/standalone.yaml and exit")
    ap.add_argument("-work-dir-name", "--work-dir-name", dest="work_dir_name", default="WORK",
                     help="top-level dir name under WORK_DIR (default: %(default)s)")
    return ap


def main():
    args = build_parser().parse_args()

    if args.list_tests:
        sys.exit(do_list(args))
    if args.lint:
        sys.exit(do_lint(args))
    if args.clean:
        sys.exit(do_clean(args))

    if args.test and args.suite:
        log.error("run_sim: --test and --suite are mutually exclusive")
        sys.exit(2)
    if args.waves and not args.test:
        log.error("run_sim: --waves requires --test")
        sys.exit(2)
    if not args.test and not args.suite:
        log.error("run_sim: nothing to do -- pass --test/--suite/--lint/--clean/--list (see --help)")
        sys.exit(2)

    if args.farm:
        log.info("run_sim: --farm requested -- running locally in parallel "
                  "(no remote scheduler configured yet)")

    if args.suite:
        sys.exit(run_suite(args))
    sys.exit(run_single_test(args))


if __name__ == "__main__":
    main()
