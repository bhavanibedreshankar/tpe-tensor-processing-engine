#!/usr/bin/env python3
"""
`verilator --lint-only` wrapper across every synthesizable block in
rtl/ -- the single source of truth for which sources/top-module/warning-
waivers each block needs (the top-level Makefile's `lint` target just
calls this). See docs/flows/build_flow.md for why `--coverage-user`-style
concerns don't apply here (lint-only never elaborates a simulation, so
the M0 Verilator-5.050-with-blanket---coverage compiler bug doesn't come
up) and why some blocks need width-cast waivers (-Wno-WIDTHEXPAND/
-Wno-WIDTHTRUNC) that others don't -- it's block-specific, not global,
which is why each block gets its own explicit flag set below rather than
one blanket suppression list.

Usage: python3 tools/lint.py [--block NAME]
"""
import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
from tools.common.logger import get_logger  # noqa: E402

log = get_logger("lint")

PKG = ["rtl/include/tpe_pkg.sv", "rtl/include/tpe_regs_pkg.sv"]
COMMON_ALL = PKG + ["rtl/common/sync_fifo.sv", "rtl/common/round_robin_arb.sv", "rtl/common/dp_ram.sv"]

# (block name, sources, top module, extra -Wno flags)
BLOCKS = [
    ("common", COMMON_ALL, "sync_fifo", []),
    ("round_robin_arb", PKG + ["rtl/common/round_robin_arb.sv"], "round_robin_arb", []),
    ("dp_ram", PKG + ["rtl/common/dp_ram.sv"], "dp_ram", []),
    ("tpe_sram", PKG + ["rtl/common/dp_ram.sv", "rtl/sram/tpe_sram.sv"], "tpe_sram", []),
    ("matrix_engine", PKG + [
        "rtl/common/dp_ram.sv", "rtl/matrix_engine/pe.sv", "rtl/matrix_engine/mac_array.sv",
        "rtl/matrix_engine/matrix_engine_ctrl.sv", "rtl/matrix_engine/matrix_engine.sv",
    ], "matrix_engine", ["UNUSEDSIGNAL", "PINCONNECTEMPTY", "UNSIGNED"]),
    ("tpe_dma", PKG + ["rtl/dma/tpe_dma.sv"], "tpe_dma", ["UNUSEDSIGNAL"]),
    ("axi4_ddr_model", ["rtl/common/dp_ram.sv", "verif/models/axi4_ddr_model.sv"], "axi4_ddr_model",
     ["UNUSEDSIGNAL"]),
    ("tpe_cmd_proc", PKG + ["rtl/common/sync_fifo.sv", "rtl/command_processor/tpe_cmd_proc.sv"],
     "tpe_cmd_proc", ["UNUSEDSIGNAL", "WIDTHEXPAND", "WIDTHTRUNC"]),
    ("tpe_scheduler", PKG + ["rtl/scheduler/tpe_scheduler.sv"], "tpe_scheduler",
     ["UNUSEDSIGNAL", "WIDTHEXPAND", "WIDTHTRUNC"]),
    ("tpe_pmu", PKG + ["rtl/pmu/tpe_pmu.sv"], "tpe_pmu", ["UNUSEDSIGNAL", "WIDTHEXPAND", "WIDTHTRUNC"]),
    ("tpe_debug", PKG + ["rtl/common/sync_fifo.sv", "rtl/debug/tpe_debug.sv"], "tpe_debug",
     ["UNUSEDSIGNAL", "WIDTHEXPAND", "WIDTHTRUNC"]),
    ("tpe_top", PKG + [
        "rtl/common/sync_fifo.sv", "rtl/common/dp_ram.sv",
        "rtl/matrix_engine/pe.sv", "rtl/matrix_engine/mac_array.sv",
        "rtl/matrix_engine/matrix_engine_ctrl.sv", "rtl/matrix_engine/matrix_engine.sv",
        "rtl/dma/tpe_dma.sv", "rtl/command_processor/tpe_cmd_proc.sv", "rtl/scheduler/tpe_scheduler.sv",
        "rtl/pmu/tpe_pmu.sv", "rtl/debug/tpe_debug.sv", "rtl/top/tpe_top.sv",
    ], "tpe_top", ["UNUSEDSIGNAL", "PINCONNECTEMPTY", "UNSIGNED", "WIDTHEXPAND", "WIDTHTRUNC"]),
]

BASE_WNO = ["DECLFILENAME", "UNUSEDPARAM"]


def lint_one(name, sources, top_module, extra_wno):
    wno = BASE_WNO + extra_wno
    cmd = ["verilator", "--lint-only", "-Wall"] + [f"-Wno-{w}" for w in wno] \
        + [str(REPO_ROOT / s) for s in sources] + ["--top-module", top_module]
    proc = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    return proc.returncode == 0, proc.stdout + proc.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--block", help="lint only this block name (default: all)")
    args = ap.parse_args()

    blocks = [b for b in BLOCKS if args.block is None or b[0] == args.block]
    if not blocks:
        log.error(f"lint: no such block {args.block!r}; known: {[b[0] for b in BLOCKS]}")
        sys.exit(1)

    failures = []
    for name, sources, top_module, extra_wno in blocks:
        ok, output = lint_one(name, sources, top_module, extra_wno)
        if ok:
            log.info(f"lint: {name}: OK")
        else:
            log.error(f"lint: {name}: FAILED")
            print(output)
            failures.append(name)

    if failures:
        log.error(f"lint: {len(failures)}/{len(blocks)} block(s) failed: {failures}")
        sys.exit(1)
    log.info(f"lint: all {len(blocks)} blocks OK")


if __name__ == "__main__":
    main()
