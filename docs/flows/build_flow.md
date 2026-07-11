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

Runs `verilator --lint-only` over the current RTL set (grows as blocks
land; from M6 onward this is wrapped by `tools/lint.py`, which adds a
waiver list for known-acceptable warnings and aggregates results across the
whole `rtl/` tree in one pass instead of the current per-file invocations).

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
