#!/usr/bin/env python3
"""
Convenience GTKWave launcher: opens a given block testbench's last waveform
dump. Equivalent to each testbench Makefile's own `make waves` target, but
callable from one place for any block without `cd`-ing into its directory
(and usable straight after a tools/regression.py run, whose last-run dump
is whatever test last executed in that directory).

Usage: python3 tools/waves.py <block>   (block = sram/matrix_engine/dma/top/pmu/debug/smoke)
"""
import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("block")
    args = ap.parse_args()

    dump = REPO_ROOT / "verif" / "cocotb_tb" / args.block / "sim_build" / "dump.vcd"
    if not dump.exists():
        print(f"waves: {dump} not found -- run `make -C verif/cocotb_tb/{args.block}` first", file=sys.stderr)
        sys.exit(1)

    subprocess.Popen(["gtkwave", str(dump)])
    print(f"waves: launched gtkwave on {dump.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
