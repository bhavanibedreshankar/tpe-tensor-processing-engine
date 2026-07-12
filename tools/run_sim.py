#!/usr/bin/env python3
"""
run_sim -- single entry point for running TPE cocotb tests without
littering the source tree with generated files, split into independently
cacheable pipeline stages so tests targeting the same block reuse each
other's build artifacts instead of recompiling from scratch every time:

    filelist     resolve a block's VERILOG_SOURCES/EXTRA_ARGS/TOPLEVEL/MODULE
                 (make -p -n against its Makefile) and hash the source
                 content -- its own directory, cached per block; the hash
                 is compile's cache key, the resolved vars feed rtl_sim
    model_build  `make -C model` (the C++ golden model the scoreboards shell
                 out to at runtime) -- global, one instance, cached
    compile      `verilator -cc --exe` + C++ build -> the block's Vtop binary
                 -- per block, SHARED/reused across every test targeting
                 that block (see section on caching below)
    rtl_sim      runs the compiled Vtop binary directly against one
                 TESTCASE/seed (bypassing make -- see that function's
                 docstring for why) -- per test, produces
                 results.xml/dump.vcd/coverage.dat

Each stage gets its own directory under $WORK_DIR with a status.json
(state/timing/log path) any of these tools can read -- see `-monitor`.

## Why compile is reusable across tests, and why rtl_sim bypasses make

`make -C verif/cocotb_tb/<dir> SIM_BUILD=<x> <x>/Vtop` (targeting the
binary file directly, not the "sim"/"regression" goal) *should* be able to
rely on Verilator's own -Mdir incremental compile (skips regenerating
unchanged output) to make repeat calls with an unchanged SIM_BUILD near-
instant. It does on a normal filesystem -- but this sandbox's project-
directory mount doesn't preserve the sub-second mtime precision that
incremental check depends on, confirmed empirically (identical repeated
compiles against /tmp correctly no-op; the same repeated compiles against
a directory under this repo's own tree never do, every time re-doing the
full ~7s build). So the `compile` stage keeps its own SHA-256 content hash
of the block's sources (computed once by `filelist`) instead of trusting
Verilator/Make's mtime-based judgment, and skips invoking `make` entirely
when the hash is unchanged. `rtl_sim` then invokes the resulting Vtop
binary *directly* (not through `make -C block_dir` again) -- any make
invocation that re-evaluates Vtop.mk's rule re-triggers Verilator (its
recipe has a phony `model` prerequisite, so GNU Make always re-runs it),
which on this filesystem means a full rebuild on every single test,
completely defeating the point. See run_rtl_sim()'s docstring for exactly
which env vars replicate what the Makefile recipe would otherwise set.

Resolves a bare test name to its block directory from
verif/testlists/standalone.yaml (the master catalog) automatically -- no
need to know or type `-C verif/cocotb_tb/<dir>` yourself. Every generated
file for a run lands under one place:

    $WORK_DIR/<work-dir-name, default "WORK">/<tag>/rtl_sim/    (--test)
    $WORK_DIR/<work-dir-name>/<suite>/<tag>/rtl_sim/            (--suite)
    $WORK_DIR/<work-dir-name>/_cache/                           (shared, reused)

where <tag> is "<dir>.<test>" (plus ".seed<N>" when seeded). WORK_DIR
comes from `source env.sh` (falls back to sim/logs/adhoc if unset, same
default env.sh uses).

This sits alongside the existing Makefile / tools/regression.py /
tools/cov_merge.py / tools/lint.py / tools/waves.py flow -- none of that
changes or is required; see docs/HANDBOOK.md and
docs/flows/run_sim_flow.md.

Examples:
    run_sim --test dma_sanity_test
    run_sim --test dma_random_test --seed 12345 --coverage --waves
    run_sim --suite smoke --jobs 8 --coverage
    run_sim --suite daily --farm
    run_sim --lint --block tpe_dma
    run_sim --clean --suite smoke
    run_sim --clean --block dma       # force a recompile of just that block
    run_sim --monitor --watch
    run_sim --list
"""
import argparse
import concurrent.futures
import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime, timezone
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

_task_lock = threading.Lock()
_model_build_done = False
_filelist_done = {}  # dir_ -> source hash
_session_tasks = []  # every record_task() call this process made, in order
_quiet_console = False  # set in main() when -monitor is active: the live monitor
                         # page is the real-time view, per-task lines would just
                         # get overwritten/duplicate it


def work_root(args) -> Path:
    work_dir = Path(os.environ.get("WORK_DIR", REPO_ROOT / "sim" / "logs" / "adhoc"))
    return work_dir / args.work_dir_name


def cache_root(args) -> Path:
    return work_root(args) / "_cache"


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


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------------------------------------------------------------------------
# Task status: every stage writes a status.json to its own directory so
# `-monitor` (or any other tool) can read live/finished state off disk.
# ---------------------------------------------------------------------------

def write_status(task_dir: Path, **fields):
    task_dir.mkdir(parents=True, exist_ok=True)
    path = task_dir / "status.json"
    data = {}
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            data = {}
    data.update(fields)
    data["dir"] = str(task_dir)
    path.write_text(json.dumps(data, indent=2))


def record_task(stage: str, scope: str, state: str, duration_s: float, note: str = ""):
    """Records one stage's outcome for the end-of-run summary (see
    print_final_summary) and, unless -monitor is live-watching this run
    (in which case its own refreshing page already shows this), prints a
    one-line notice."""
    with _task_lock:
        _session_tasks.append({"stage": stage, "scope": scope, "state": state,
                                "duration_s": duration_s, "note": note})
    if not _quiet_console:
        extra = f" ({note})" if note else ""
        print(f"[{stage}] {scope}: {state} ({duration_s:.2f}s){extra}")


# ---------------------------------------------------------------------------
# Stage 1: filelist -- resolve a block's compile inputs and hash them.
# This hash is the real cache key for the compile stage below (not
# Verilator/Make's own mtime-based judgment -- see the module docstring).
# ---------------------------------------------------------------------------

def _extract_make_var(make_p_output: str, name: str) -> str:
    for line in make_p_output.splitlines():
        if line.startswith(name + " ") and "=" in line:
            return line[line.index("=") + 1:].strip()
    return ""


def _hash_sources(sources: list, extra_args: str, toplevel: str, module: str) -> str:
    """Content hash (not mtime-based -- this sandbox's project-directory
    mount doesn't preserve the sub-second mtime precision Verilator's own
    -Mdir incremental cache depends on, confirmed empirically: identical
    `make SIM_BUILD=<x> <x>/Vtop` invocations against an unchanged /tmp
    dir correctly no-op on repeat, the same invocation against a dir
    under this repo's own tree never does. Hashing file *content* instead
    makes the compile-stage cache below correct regardless of the
    filesystem's mtime behavior)."""
    h = hashlib.sha256()
    for src in sources:
        p = Path(src)
        if p.exists():
            h.update(p.read_bytes())
        h.update(src.encode())
    h.update(extra_args.encode())
    h.update(toplevel.encode())
    h.update(module.encode())
    return h.hexdigest()


def run_filelist(croot: Path, dir_: str) -> dict:
    block_dir = REPO_ROOT / "verif" / "cocotb_tb" / dir_
    task_dir = croot / dir_ / "filelist"
    start = time.time()
    write_status(task_dir, stage="filelist", scope=dir_, state="RUNNING", start=_now())

    proc = subprocess.run(["make", "-C", str(block_dir), "-p", "-n"], env=venv_env({}),
                           capture_output=True, text=True)
    sources = _extract_make_var(proc.stdout, "VERILOG_SOURCES").split()
    extra_args = _extract_make_var(proc.stdout, "EXTRA_ARGS")
    toplevel = _extract_make_var(proc.stdout, "TOPLEVEL")
    module = _extract_make_var(proc.stdout, "MODULE")
    source_hash = _hash_sources(sources, extra_args, toplevel, module)

    task_dir.mkdir(parents=True, exist_ok=True)
    (task_dir / "sources.txt").write_text("\n".join(sources) + "\n")
    (task_dir / "vars.json").write_text(json.dumps(
        {"TOPLEVEL": toplevel, "MODULE": module, "EXTRA_ARGS": extra_args}, indent=2))
    (task_dir / "hash.txt").write_text(source_hash + "\n")

    duration = time.time() - start
    state = "DONE" if sources else "FAIL"
    write_status(task_dir, state=state, duration_s=duration, end=_now())
    return {"stage": "filelist", "scope": dir_, "state": state, "duration_s": duration,
            "hash": source_hash, "toplevel": toplevel, "module": module, "extra_args": extra_args}


def ensure_filelist(croot: Path, dir_: str) -> dict:
    """Returns {"hash", "toplevel", "module", "extra_args"} for dir_,
    recomputing (once per dir_ per run_sim invocation) only the first
    time it's asked for. `hash` feeds run_compile()'s cache check;
    `toplevel`/`module`/`extra_args` feed run_rtl_sim()'s direct
    invocation of the compiled binary (see that function's docstring)."""
    with _task_lock:
        cached = _filelist_done.get(dir_)
    if cached is not None:
        return cached
    r = run_filelist(croot, dir_)
    record_task(r["stage"], r["scope"], r["state"], r["duration_s"])
    info = {"hash": r["hash"], "toplevel": r["toplevel"], "module": r["module"],
            "extra_args": r["extra_args"]}
    with _task_lock:
        _filelist_done[dir_] = info
    return info


# ---------------------------------------------------------------------------
# Stage 2: model_build -- global, shared C++ golden-model build.
# ---------------------------------------------------------------------------

def run_model_build(croot: Path) -> dict:
    task_dir = croot / "model_build"
    start = time.time()
    write_status(task_dir, stage="model_build", scope="model", state="RUNNING", start=_now())

    proc = subprocess.run(["make", "-C", str(REPO_ROOT / "model")], env=venv_env({}),
                           capture_output=True, text=True)
    task_dir.mkdir(parents=True, exist_ok=True)
    (task_dir / "build.log").write_text(proc.stdout + proc.stderr)

    cached = "Nothing to be done" in proc.stdout
    state = "PASS" if proc.returncode == 0 else "FAIL"
    duration = time.time() - start
    write_status(task_dir, state=state, cached=cached, duration_s=duration, end=_now())
    return {"stage": "model_build", "scope": "model", "state": state,
            "duration_s": duration, "note": "cached" if cached else "built"}


def ensure_model_build(croot: Path) -> bool:
    global _model_build_done
    with _task_lock:
        already = _model_build_done
        _model_build_done = True
    if already:
        return True
    r = run_model_build(croot)
    record_task(r["stage"], r["scope"], r["state"], r["duration_s"], r["note"])
    return r["state"] == "PASS"


# ---------------------------------------------------------------------------
# Stage 3: compile -- per block, shared Vtop binary. Always invoked (cheap
# when unchanged, since Verilator/make skip real work), but genuinely
# rebuilds when RTL/testbench sources change.
# ---------------------------------------------------------------------------

def run_compile(croot: Path, dir_: str, source_hash: str) -> dict:
    block_dir = REPO_ROOT / "verif" / "cocotb_tb" / dir_
    task_dir = croot / dir_ / "compile"
    sim_build = task_dir / "sim_build"
    vtop = sim_build / "Vtop"
    built_hash_file = task_dir / "built_hash.txt"

    start = time.time()

    # Real cache check: skip invoking make entirely if the block's source
    # hash (from the filelist stage) matches what's already built. Doesn't
    # rely on Verilator's own -Mdir mtime-based incremental compile, which
    # this sandbox's project-directory mount doesn't preserve precisely
    # enough for -- see _hash_sources()'s docstring.
    if vtop.exists() and built_hash_file.exists() and built_hash_file.read_text().strip() == source_hash:
        duration = time.time() - start
        write_status(task_dir, stage="compile", scope=dir_, state="PASS", start=_now(),
                     cached=True, duration_s=duration, end=_now())
        return {"stage": "compile", "scope": dir_, "state": "PASS", "duration_s": duration,
                "cached": True, "note": "cached", "sim_build": sim_build}

    write_status(task_dir, stage="compile", scope=dir_, state="RUNNING", start=_now())
    proc = subprocess.run(["make", "-C", str(block_dir), f"SIM_BUILD={sim_build}", str(vtop)],
                          env=venv_env({}), capture_output=True, text=True)
    task_dir.mkdir(parents=True, exist_ok=True)
    (task_dir / "build.log").write_text(proc.stdout + proc.stderr)

    ok = proc.returncode == 0 and vtop.exists()
    if ok:
        built_hash_file.write_text(source_hash + "\n")
    state = "PASS" if ok else "FAIL"
    duration = time.time() - start
    write_status(task_dir, state=state, cached=False, duration_s=duration, end=_now())
    return {"stage": "compile", "scope": dir_, "state": state, "duration_s": duration,
            "cached": False, "note": "built", "sim_build": sim_build}


# ---------------------------------------------------------------------------
# Stage 4: rtl_sim -- per test, runs the (shared, cached) compiled binary.
# ---------------------------------------------------------------------------

def sweep_generated(block_dir: Path, task_dir: Path, cov_root: Path, tag: str, keep_coverage: bool):
    """Moves/copies the artifacts a test writes at hardcoded relative
    paths inside block_dir -- can't be redirected via make/env vars, see
    scoreboard.py's `Path("<block>_scoreboard_work")` and sram's
    `Path("sram_coverage.xml")` -- into task_dir/cov_root, then removes
    them from the source tree so it's clean again. The TB-side coverage
    XML is only kept (copied into cov_root) when `-coverage` was actually
    requested; otherwise it's discarded, same as coverage.dat below."""
    for p in sorted(block_dir.glob("*_scoreboard_work")):
        dest = task_dir / p.name
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


_libpython_loc = None


def get_libpython() -> str:
    """`cocotb-config --libpython`, memoized -- doesn't change for the life
    of a run_sim invocation."""
    global _libpython_loc
    if _libpython_loc is None:
        proc = subprocess.run([str(VENV / "bin" / "cocotb-config"), "--libpython"],
                              capture_output=True, text=True, check=True)
        _libpython_loc = proc.stdout.strip()
    return _libpython_loc


def run_rtl_sim(dir_: str, test: str, seed, result_dir: Path, sim_build: Path, filelist: dict,
                 timeout_s: int, cov_root: Path = None, keep_coverage: bool = False,
                 keep_waves: bool = False) -> dict:
    """Invokes the already-compiled Vtop binary directly (cwd=block_dir,
    not through `make -C block_dir`). Going through make here would
    re-evaluate Vtop.mk's rule chain -- which depends on the phony `model`
    target (verif/cocotb_tb/*/Makefile), so GNU Make always re-runs its
    recipe (`verilator -cc`) even when nothing changed. On a filesystem
    with reliable mtimes that's a harmless ~1-2s no-op re-verify, but this
    sandbox's project-directory mount doesn't preserve the mtime precision
    Verilator's own -Mdir incremental check needs (see _hash_sources), so
    that "harmless" re-invocation turns into a full ~7s rebuild every
    single test. Bypassing make for this stage entirely -- replicating
    just the run-time env vars/argv Makefile.verilator's own recipe sets
    (MODULE/TESTCASE/TOPLEVEL/TOPLEVEL_LANG/COCOTB_RESULTS_FILE/
    LIBPYTHON_LOC/PYTHONPATH), using TOPLEVEL/MODULE/EXTRA_ARGS resolved
    by the filelist stage -- sidesteps the whole problem."""
    block_dir = REPO_ROOT / "verif" / "cocotb_tb" / dir_
    tag = tag_for(dir_, test, seed)
    task_dir = result_dir / "rtl_sim"
    task_dir.mkdir(parents=True, exist_ok=True)
    cov_root = cov_root or (result_dir / "coverage")

    results_xml = task_dir / "results.xml"
    dump_vcd = task_dir / "dump.vcd"
    coverage_dat = task_dir / "coverage.dat"
    log_file = task_dir / "run.log"

    write_status(task_dir, stage="rtl_sim", scope=tag, state="RUNNING", start=_now())

    env = venv_env({
        "PYTHONPATH": f"{REPO_ROOT}:{os.environ.get('PYTHONPATH', '')}",
        "LIBPYTHON_LOC": get_libpython(),
        "MODULE": filelist["module"],
        "TESTCASE": test,
        "TOPLEVEL": filelist["toplevel"],
        "TOPLEVEL_LANG": "verilog",
        "COCOTB_RESULTS_FILE": str(results_xml),
    })
    if seed is not None:
        env["TPE_SEED"] = str(seed)

    argv = [str(sim_build / "Vtop"), "--trace-file", str(dump_vcd)] \
        + filelist["extra_args"].split() \
        + [f"+verilator+coverage+file+{coverage_dat}"]

    start = time.time()
    timed_out = False
    try:
        proc = subprocess.run(argv, cwd=block_dir, env=env,
                               capture_output=True, text=True, timeout=timeout_s)
        stdout = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        timed_out = True
        stdout = (e.stdout or "") + (e.stderr or "") + f"\n--- TIMEOUT after {timeout_s}s ---\n"
    wall_s = time.time() - start
    log_file.write_text(stdout)

    sweep_generated(block_dir, task_dir, cov_root, tag, keep_coverage)

    # Every block Makefile hardcodes --coverage-line/-toggle/-user and
    # --trace/--trace-structs (see docs/flows/build_flow.md section 4), so
    # Verilator always instruments coverage and always traces regardless of
    # -coverage/-waves. Since sim_build is now a SHARED cache dir (reused
    # across tests), coverage.dat/dump.vcd must be written per-test into
    # task_dir (not sim_build) -- discard them here if not actually asked
    # for, rather than leaving them lying around unrequested.
    if keep_coverage and coverage_dat.exists():
        cov_root.mkdir(parents=True, exist_ok=True)
        shutil.copy(coverage_dat, cov_root / f"{tag}.dat")
    elif not keep_coverage and coverage_dat.exists():
        coverage_dat.unlink()
    if not keep_waves and dump_vcd.exists():
        dump_vcd.unlink()

    if timed_out:
        status, cocotb_time_s = "TIMEOUT", None
    else:
        status, cocotb_time_s = parse_results_xml(results_xml, test)

    write_status(task_dir, state=status, duration_s=wall_s, end=_now())
    record_task("rtl_sim", tag, status, wall_s)

    return {
        "tag": tag, "dir": dir_, "test": test, "seed": seed, "status": status,
        "wall_s": wall_s, "cocotb_time_s": cocotb_time_s,
        "result_dir": result_dir, "log": log_file, "dump_vcd": dump_vcd,
    }


def run_test(dir_: str, test: str, seed, result_dir: Path, timeout_s: int, croot: Path,
             cov_root: Path = None, keep_coverage: bool = False, keep_waves: bool = False) -> dict:
    """Runs the full stage pipeline for one test: model_build and filelist
    are shared/cached (run once per run_sim invocation), compile is shared
    per block (skips real work when the shared sim_build is already up to
    date), rtl_sim is per test."""
    ensure_model_build(croot)
    filelist = ensure_filelist(croot, dir_)

    compile_result = run_compile(croot, dir_, filelist["hash"])
    record_task(compile_result["stage"], compile_result["scope"], compile_result["state"],
               compile_result["duration_s"], compile_result["note"])
    if compile_result["state"] != "PASS":
        tag = tag_for(dir_, test, seed)
        log.error(f"run_sim: compile failed for dir={dir_} -- see "
                  f"{croot / dir_ / 'compile' / 'build.log'}")
        return {"tag": tag, "dir": dir_, "test": test, "seed": seed, "status": "ERROR",
                "wall_s": compile_result["duration_s"], "cocotb_time_s": None,
                "result_dir": result_dir, "log": croot / dir_ / "compile" / "build.log",
                "dump_vcd": None}

    return run_rtl_sim(dir_, test, seed, result_dir, compile_result["sim_build"], filelist,
                        timeout_s, cov_root=cov_root, keep_coverage=keep_coverage,
                        keep_waves=keep_waves)


def run_group(entries: list, suite_root: Path, timeout_s: int, croot: Path, keep_coverage: bool) -> list:
    cov_root = suite_root / "coverage"
    out = []
    for e in entries:
        seed = e.get("seed")
        tag = tag_for(e["dir"], e["test"], seed)
        out.append(run_test(e["dir"], e["test"], seed, suite_root / tag, timeout_s, croot,
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


def _parse_coverage_summary(path: Path) -> str:
    """Condenses verilator_coverage's summary report (line/toggle/branch/
    covergroup % from its first few lines, before the per-hierarchy
    breakdown) into one line for print_final_summary -- the full report
    is still written in full to `path` for anyone who wants it."""
    bits = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.endswith(":"):
            if bits:
                break  # reached "Hierarchy Coverage Summary:" or similar
            continue
        if ":" not in line or "%" not in line:
            continue
        name, _, rest = line.partition(":")
        if name.strip() in ("line", "toggle", "branch", "covergroup"):
            bits.append(f"{name.strip()} {rest.strip().split()[0]}")
    return ", ".join(bits) if bits else "see coverage_summary.txt"


def report_coverage(cov_dir: Path, annotate: bool) -> dict:
    """Merges/reports coverage via tools/cov_merge.py, but swallows its
    verbose per-hierarchy console dump (still written in full to
    coverage_summary.txt) -- only a start/processing/done notice and any
    error surface on the console; print_final_summary shows the condensed
    score."""
    log.info("run_sim: coverage: started")
    if not cov_dir.exists():
        msg = f"no coverage under {cov_dir}, nothing to merge"
        log.warning(f"run_sim: coverage: {msg}")
        return {"error": msg}

    log.info("run_sim: coverage: processing...")
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            merge_verilator(cov_dir, annotate)
            merge_cocotb_coverage(cov_dir)
    except Exception as exc:
        log.error(f"run_sim: coverage: FAILED -- {exc}")
        return {"error": str(exc)}

    summary_path = cov_dir.parent / "coverage_summary.txt"
    summary = _parse_coverage_summary(summary_path) if summary_path.exists() else "n/a"
    log.info("run_sim: coverage: done")
    return {"summary": summary, "path": summary_path}


def open_waves(dump_vcd: Path) -> bool:
    if not dump_vcd.exists():
        log.warning(f"run_sim: no waveform at {dump_vcd} (did tracing run?)")
        return False
    gtkwave = shutil.which("gtkwave")
    if not gtkwave:
        log.error("run_sim: gtkwave not found on PATH")
        return False
    subprocess.Popen([gtkwave, str(dump_vcd)])
    log.info(f"run_sim: launched gtkwave on {dump_vcd}")
    return True


def print_final_summary(coverage_result: dict = None, waves_opened: Path = None):
    """Printed at the end of every -test/-suite run: a stage-by-stage
    breakdown of everything record_task() saw this process do, plus
    coverage/waves sections -- only shown when that feature was actually
    enabled this run."""
    with _task_lock:
        tasks = list(_session_tasks)

    by_stage = defaultdict(lambda: {"count": 0, "cached": 0, "ok": 0, "bad": 0, "total_s": 0.0})
    for t in tasks:
        d = by_stage[t["stage"]]
        d["count"] += 1
        d["total_s"] += t["duration_s"]
        if t["note"] == "cached":
            d["cached"] += 1
        if t["state"] in ("PASS", "DONE"):
            d["ok"] += 1
        elif t["state"] in ("FAIL", "ERROR", "TIMEOUT"):
            d["bad"] += 1

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print("Tasks:")
    for stage in ("model_build", "filelist", "compile", "rtl_sim"):
        d = by_stage.get(stage)
        if not d:
            continue
        bits = f"{d['count']} run"
        if d["cached"]:
            bits += f", {d['cached']} cached"
        if stage == "rtl_sim":
            bits += f" -- {d['ok']} passed, {d['bad']} failed"
        elif d["bad"]:
            bits += f" -- {d['bad']} failed"
        print(f"  {stage:<12}: {bits} ({d['total_s']:.1f}s)")

    if coverage_result is not None:
        print("\nCoverage:")
        if coverage_result.get("error"):
            print(f"  ERROR: {coverage_result['error']}")
        else:
            print(f"  {coverage_result['summary']}")
            print(f"  full report: {coverage_result['path']}")

    if waves_opened is not None:
        print(f"\nWaves: {waves_opened} (opened in GTKWave)")

    print("=" * 60)


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

    r = run_test(entry["dir"], args.test, args.seed, result_dir, args.timeout, cache_root(args),
                 keep_coverage=args.coverage, keep_waves=args.waves)
    print(f"\n{r['tag']:<50} {r['status']:<8} {r['wall_s']:>8.2f}s")
    print(f"log: {r['log']}")
    if entry.get("expect_fail") and r["status"] == "FAIL":
        print(f"note: FAIL expected -- see docs/verification/bug_list.md ({entry['expect_fail']})")

    coverage_result = report_coverage(result_dir / "coverage", args.annotate) if args.coverage else None
    waves_opened = None
    if args.waves and r["dump_vcd"] is not None and open_waves(r["dump_vcd"]):
        waves_opened = r["dump_vcd"]

    print_final_summary(coverage_result, waves_opened)
    return 0 if r["status"] == "PASS" else 1


def run_suite(args) -> int:
    entries = load_testlist(args.suite)
    suite_root = work_root(args) / args.suite
    croot = cache_root(args)

    groups = defaultdict(list)
    for e in entries:
        groups[e["dir"]].append(e)

    log.info(f"run_sim: suite={args.suite} tests={len(entries)} dirs={len(groups)} "
             f"jobs={args.jobs} -> {suite_root}")

    start = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futures = {ex.submit(run_group, es, suite_root, args.timeout, croot, args.coverage): d
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

    coverage_result = report_coverage(suite_root / "coverage", args.annotate) if args.coverage else None
    print_final_summary(coverage_result)

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

    if args.block:
        rm(cache_root(args) / args.block)
        return 0
    if args.suite:
        rm(root / args.suite)
        return 0
    if args.test:
        catalog = load_catalog()
        entry = catalog.get(args.test)
        prefix = f"{entry['dir']}.{args.test}" if entry else args.test
        matches = sorted(p for p in root.glob(f"{prefix}*")) if root.exists() else []
        if not matches:
            log.warning(f"run_sim: nothing under {root} matches {args.test!r}")
        for p in matches:
            rm(p)
        return 0
    rm(root)
    return 0


# ---------------------------------------------------------------------------
# Task monitor -- reads every status.json under the work root (written by
# the stages above) and prints their current state. `-watch` re-polls so
# it can be run in a second terminal alongside a live -suite/-test run.
# ---------------------------------------------------------------------------

def _read_statuses(root: Path) -> list:
    statuses = []
    if not root.exists():
        return statuses
    for p in sorted(root.rglob("status.json")):
        try:
            data = json.loads(p.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        statuses.append(data)
    return statuses


def _print_monitor(root: Path):
    statuses = _read_statuses(root)
    if not statuses:
        print(f"run_sim -monitor: no tasks found under {root} (nothing has run yet)")
        return
    statuses.sort(key=lambda s: s.get("start") or "")
    print(f"{'STAGE':<12} {'SCOPE':<32} {'STATE':<9} {'DURATION':>9}  NOTES")
    print("-" * 80)
    for s in statuses:
        stage = s.get("stage", "?")
        scope = s.get("scope", "?")
        state = s.get("state", "?")
        if state == "RUNNING" and s.get("start"):
            try:
                started = datetime.fromisoformat(s["start"])
                duration = (datetime.now(timezone.utc) - started).total_seconds()
            except ValueError:
                duration = s.get("duration_s") or 0.0
            dur_str = f"{duration:>8.1f}s"
        else:
            dur_str = f"{s.get('duration_s', 0.0):>8.2f}s"
        note = "cached" if s.get("cached") else ""
        print(f"{stage:<12} {scope:<32} {state:<9} {dur_str:>9}  {note}")


def do_monitor(args) -> int:
    """Standalone `-monitor` (no -test/-suite in this same invocation): a
    snapshot of whatever the last run left behind, or -- with -watch -- a
    full-screen live-refreshing view of it. See _monitor_background()
    for the combined `-monitor -test/-suite` case, which live-monitors
    the run this same process is driving."""
    root = work_root(args)
    if not args.watch:
        _print_monitor(root)
        return 0
    try:
        while True:
            print("\033[2J\033[H", end="")  # clear screen, home cursor
            print(f"run_sim monitor -- {root} (Ctrl-C to stop)\n")
            _print_monitor(root)
            time.sleep(2)
    except KeyboardInterrupt:
        print()
    return 0


def _monitor_background(root: Path, stop_event: threading.Event, interval: float = 1.0):
    """Runs in a daemon thread alongside a live -test/-suite run (started
    from main() when -monitor is combined with either): a single page,
    cleared and redrawn every `interval` seconds -- not a scrolling feed
    -- until `stop_event` is set once the run finishes. Per-task console
    lines (record_task) are suppressed for the run's duration (see
    `_quiet_console`) so this page is the only thing moving."""
    while not stop_event.is_set():
        print("\033[2J\033[H", end="")  # clear screen, home cursor
        print(f"run_sim monitor -- {root}\n")
        _print_monitor(root)
        stop_event.wait(interval)


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
                     help="with --lint, lint only this block; with --clean, remove only that "
                          "block's compile cache")
    ap.add_argument("-waves", "--waves", dest="waves", action="store_true",
                     help="open GTKWave on the run's dump.vcd afterward (requires --test)")
    ap.add_argument("-clean", "--clean", dest="clean", action="store_true",
                     help="remove work dirs under WORK_DIR/<work-dir-name> "
                          "(scope with --test/--suite/--block, or everything if none given)")
    ap.add_argument("-monitor", "--monitor", dest="monitor", action="store_true",
                     help="combined with --test/--suite: live-print every task's status "
                          "(filelist/model_build/compile/rtl_sim) every 2s until that run "
                          "completes. Standalone (no --test/--suite): print the last run's "
                          "final status and exit -- add --watch to keep re-polling that instead")
    ap.add_argument("-watch", "--watch", dest="watch", action="store_true",
                     help="with a standalone --monitor (no --test/--suite), keep re-polling "
                          "every 2s (Ctrl-C to stop) instead of a single snapshot -- e.g. from a "
                          "second terminal watching a --test/--suite run in a first one")
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

    # Standalone -monitor (no -test/-suite in this invocation): just report
    # on whatever's already on disk and exit. Combined with -test/-suite,
    # -monitor instead live-watches *this* run below.
    if args.monitor and not (args.test or args.suite):
        sys.exit(do_monitor(args))

    if args.test and args.suite:
        log.error("run_sim: --test and --suite are mutually exclusive")
        sys.exit(2)
    if args.waves and not args.test:
        log.error("run_sim: --waves requires --test")
        sys.exit(2)
    if not args.test and not args.suite:
        log.error("run_sim: nothing to do -- pass --test/--suite/--lint/--clean/--list/--monitor "
                   "(see --help)")
        sys.exit(2)

    if args.farm:
        log.info("run_sim: --farm requested -- running locally in parallel "
                  "(no remote scheduler configured yet)")

    monitor_thread = None
    stop_event = threading.Event()
    if args.monitor:
        global _quiet_console
        _quiet_console = True  # the monitor page is the real-time view now
        monitor_thread = threading.Thread(
            target=_monitor_background, args=(work_root(args), stop_event), daemon=True)
        monitor_thread.start()

    try:
        rc = run_suite(args) if args.suite else run_single_test(args)
    finally:
        if monitor_thread:
            stop_event.set()
            monitor_thread.join(timeout=5)

    sys.exit(rc)


if __name__ == "__main__":
    main()
