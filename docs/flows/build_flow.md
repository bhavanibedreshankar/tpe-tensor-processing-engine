# Build Flow

How source becomes something you can simulate, in the order it actually
happens.

## 1. Environment setup

```
make venv       # creates .venv/, installs tools/requirements.txt
                # (cocotb, cocotb-coverage, pyuvm, pytest, pyyaml, jinja2, numpy)
```

Verilator, Icarus Verilog, and GTKWave are installed at the OS level (via
Homebrew on macOS) rather than through the venv -- see the
[README](../../README.md#toolchain) for exact versions and install
commands.

## 2. Register map generation

`docs/register_map/tpe_regs.yaml` is the single source of truth for every
MMIO register. Nothing downstream should hand-edit generated register
constants.

```
make regmap
```

regenerates:
- `rtl/include/tpe_regs_pkg.sv` (SV localparams, consumed by
  `rtl/command_processor/`, `rtl/dma/`, etc.)
- `model/include/tpe_regs.h` (C++ constexpr header, consumed by the golden
  model and pyuvm register-access sequences)
- `docs/register_map/generated/register_map.md` (human-readable tables)

Run this after any edit to the YAML, and check in the regenerated files
alongside the YAML change (they are tracked in git, not gitignored, so
diffs are reviewable).

## 3. Lint

```
make lint
```

Runs `verilator --lint-only` over every synthesizable block in `rtl/`,
driven by `tools/lint.py` (the single source of truth for each block's
source list/top-module/warning-waivers -- see that file's docstring for
why some blocks need width-cast waivers others don't).

## 4. Per-block simulation build

Each block's testbench lives in `verif/cocotb_tb/<block>/` with its own
`Makefile` using cocotb's standard Makefile-based flow
(`include $(shell cocotb-config --makefiles)/Makefile.sim`) targeting
Verilator by default (`SIM=verilator`). The pattern established by the
toolchain smoke test (`verif/cocotb_tb/smoke/Makefile`) is:

```make
SIM ?= verilator
TOPLEVEL := <dut_module_name>
MODULE   := test_<block>
VERILOG_SOURCES := <abspath to the block's .sv files>
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user \
              -Wall -Wno-DECLFILENAME --trace --trace-structs
include $(shell cocotb-config --makefiles)/Makefile.sim
```

**Important**: always request the three coverage kinds explicitly. The
blanket `--coverage` flag crashes Verilator 5.050's compiler
(`V3Localize.cpp:203`) whenever a concurrent SVA assertion using `|=>` or
`disable iff` is present anywhere in the compiled design -- see
`verif/cocotb_tb/smoke/Makefile` for the discovery notes. This affects
every block's Makefile, not just the smoke test.

Build artifacts (`sim_build/`, `coverage.dat`, `dump.vcd`, `results.xml`)
are gitignored and reproducible from source at any time via `make`.

## 5. C++ golden model

```
cd model && make
```

Builds `model/tpe_model`, the golden-model CLI the pyuvm scoreboards shell
out to. See `model/README.md` (added in M1) for its build/test flow.

## 6. Everything at once

```
make toolchain-smoke   # proves the chain works, independent of real RTL
```

Full per-milestone build+sim targets (`make sim-<block>`) are added as each
block lands; see the top-level [README](../../README.md) for current
status.

## 7. Debug verbosity

Every RTL block (and the C++ golden model, see `model/README.md`) has
leveled debug prints -- `NONE` (default, silent, no behavior/timing
change), `LOW`, `MEDIUM`, `HIGH`, `DEBUG` -- mirroring UVM's
`uvm_verbosity` naming without depending on UVM itself:

```
+VERBOSITY=DEBUG   # SIM_ARGS/PLUSARGS to a block's compiled Vtop binary
TPE_VERBOSITY=DEBUG   # env var for the C++ golden model
```

`run_sim -verbosity <LEVEL>` sets both at once for a real test run,
including the golden model when a scoreboard invokes it mid-test (see
`docs/flows/run_sim_flow.md`). `rtl/include/tpe_verbosity.svh` defines
the `` `TPE_LOG_LOW/MEDIUM/HIGH/DEBUG(name, msg)`` macros every
instrumented block uses -- listed as an explicit compile-unit source
(not `` `include``d) in every block's `VERILOG_SOURCES`/`tools/lint.py`
entry, ahead of `tpe_pkg.sv`, since Verilator resolves a quoted
`` `include`` path relative to the invoking process's CWD (which differs
between `lint.py` and the real per-block Makefile compile) rather than
the including file's own directory -- an explicit source entry sidesteps
that entirely, since `` `define``s apply globally in file-list order
regardless of extension.
