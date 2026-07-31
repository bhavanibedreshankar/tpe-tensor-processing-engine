# Full-Chip Filelist & Compiled-Design Dump

`rtl/filelist.f` is a standalone Verilator `-f` filelist covering the
*entire* `rtl/` tree -- every synthesizable source, in dependency/compile
order. It exists alongside (not instead of) the per-block
`VERILOG_SOURCES` lists in `verif/cocotb_tb/*/Makefile` and
`tools/lint.py`: those stay narrow on purpose (only what each block/test
needs); this file is for whole-design tooling -- e.g. dumping the full
elaborated design for an external database/analysis tool -- that wants
one `-f` argument instead of hand-copying a source list.

## Contents

```
rtl/include/tpe_verbosity.svh
rtl/include/tpe_pkg.sv
rtl/include/tpe_regs_pkg.sv

rtl/common/sync_fifo.sv
rtl/common/round_robin_arb.sv
rtl/common/dp_ram.sv

rtl/sram/tpe_sram.sv

rtl/matrix_engine/pe.sv
rtl/matrix_engine/mac_array.sv
rtl/matrix_engine/matrix_engine_ctrl.sv
rtl/matrix_engine/matrix_engine.sv

rtl/dma/tpe_dma.sv

rtl/command_processor/tpe_cmd_proc.sv

rtl/scheduler/tpe_scheduler.sv

rtl/pmu/tpe_pmu.sv

rtl/debug/tpe_debug.sv

rtl/top/tpe_top.sv
```

`tpe_verbosity.svh` and the two packages come first for the same reason
`docs/flows/build_flow.md` section 7 gives for every per-block list: the
`` `TPE_LOG_* `` macros aren't `` `include``d, they're resolved by file-list
order, so the header defining them has to compile first.

`tpe_sram.sv` and `round_robin_arb.sv` are included even though neither
is instantiated under `tpe_top` today -- `tpe_sram` is a verified
standalone/reusable block reserved for a future V2+ scheduler
(`rtl/top/tpe_top.sv`'s header comment), and `round_robin_arb` is a
reusable common primitive (`rtl/README.md`) with no consumer yet. Both
are still part of "the design" this filelist covers; a `--top-module
tpe_top` run simply doesn't elaborate them.

## Compiling with it

```
verilator --lint-only -Wall -f rtl/filelist.f --top-module tpe_top
verilator -cc -f rtl/filelist.f --top-module tpe_top
```

Run from the repo root -- all paths in the file are repo-root-relative.

## Dumping the compiled/elaborated design (JSON AST)

This Verilator build (5.050) has no `--xml-only`/`--xml-output` --
Verilator dropped XML AST dumping in favor of JSON. `--json-only`
(+ `--json-only-meta-output` for the companion symbol/type metadata) is
the direct equivalent. Command used to generate the design database
under `/Users/bhavanibs/Documents/Claude/tpe_database/`:

```
verilator \
    --json-only \
    --json-only-output /Users/bhavanibs/Documents/Claude/tpe_database/design.tree.json \
    --json-only-meta-output /Users/bhavanibs/Documents/Claude/tpe_database/design.meta.json \
    -Wall -Wno-fatal \
    -f rtl/filelist.f \
    --top-module tpe_top > /Users/bhavanibs/Documents/Claude/tpe_database/verilator.log 2>&1
```

Notes on the flags:
- `-f rtl/filelist.f --top-module tpe_top` -- the filelist already
  contains `tpe_top.sv` as its last entry, so there's no separate
  `top.sv` argument to pass.
- `-Wno-fatal` -- without it, Verilator's default is to abort the run
  once *any* `-Wall` warning fires. This design currently produces 167
  warnings under `--top-module tpe_top` (`UNUSEDPARAM`, `UNSIGNED`,
  `UNUSEDSIGNAL`, `PINCONNECTEMPTY`, ...) -- the same waivable set
  `tools/lint.py`'s `tpe_top` entry already suppresses explicitly rather
  than via a blanket `-Wno-fatal`. For a one-off database dump,
  `-Wno-fatal` is simpler than repeating that per-flag waiver list; use
  the explicit `-Wno-<CODE>` flags from `tools/lint.py` instead if you
  need a clean (warning-free) log.

Output:
- `design.tree.json` -- the full elaborated AST (`.tree.json`)
- `design.meta.json` -- companion type/symbol metadata (`.meta.json`)
- `verilator.log` -- captured stdout+stderr (warnings + verilation
  report), exit code 0

Both JSON files were validated with `python3 -c "import json;
json.load(open(...))"` after generation.
