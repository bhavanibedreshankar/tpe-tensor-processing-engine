# TPE -- Tensor Processing Engine

## Continuous Integration

[![Lint + Smoke](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/lint-smoke.yml/badge.svg)](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/lint-smoke.yml)
[![Daily Regression](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/daily-regression.yml/badge.svg)](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/daily-regression.yml)
[![Random Regression](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/random-regression.yml/badge.svg)](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions/workflows/random-regression.yml)

- Three separate workflows (`.github/workflows/lint-smoke.yml`,
  `daily-regression.yml`, `random-regression.yml`), each named for what
  it runs, so each badge/link is unambiguous and its click-through is
  always that workflow's own run history -- no query filtering needed.
- **Lint + Smoke** runs on every push/PR (plus manual dispatch).
- **Daily Regression** runs on the 06:00 UTC cron (plus manual dispatch).
- **Random Regression** is manual-dispatch-only.
- **A green badge means infrastructure health, not zero test failures.**
  This repo's RTL has intentionally injected bugs
  ([`docs/verification/bug_list.md`](docs/verification/bug_list.md)) that
  are *expected* to FAIL every run -- `run_sim`'s exit code only goes
  nonzero on an `ERROR`/`TIMEOUT` (the harness itself breaking), so a
  catalogued-bug FAIL shows up in the run's JUnit artifact without
  reddening the badge. Cross-check any FAIL against the bug list before
  treating it as a regression.
- See [`docs/flows/ci_flow.md`](docs/flows/ci_flow.md) for the full flow.

**[→ Interactive project overview](https://bhavanibedreshankar.github.io/tpe-tensor-processing-engine/)**
-- a visual, no-chip-background-required walkthrough of what this chip
does and how a command flows through it.

A from-scratch, production-flow-style ASIC/RTL project: a small TPU-like
matrix-multiply accelerator plus a full open-source verification
environment (C++ golden model, pyuvm/cocotb testbenches, SVA assertions,
functional+structural+FSM coverage, Make-based build system, Python
regression/orchestration tooling, CI). See [`overview`](overview) for the
original product vision and [`docs/architecture/tpe_architecture_spec.md`](docs/architecture/tpe_architecture_spec.md)
for the RTL-facing spec this repo actually implements.

**Everything here uses only free/open-source tools** -- no paid EDA
licenses. See [Toolchain](#toolchain) below.

## Architecture overview

TPE is a memory-mapped coprocessor: a host writes commands to an
AXI4-Lite register window, the Command Processor decodes and queues them,
the Scheduler dispatches DMA and Matrix Engine work, results land back in
DDR via DMA, and completion raises an interrupt.

```
Host --AXI4-Lite MMIO--> Command Processor --> Scheduler --+--> DMA Engine ---AXI4---> DDR
                              ^                             |         |
                              |                             |         v
                          Debug/PMU <--------events----------+   Local SRAM (scratchpad)
                                                              |         ^
                                                              v         |
                                                        Matrix Compute Engine
                                                     (MAC array + accumulator)
```

| Block | Directory | What it does |
|---|---|---|
| Command Processor | `rtl/command_processor/` | Front door -- AXI4-Lite MMIO slave; stages a command's opcode/tag/addresses/dims, enqueues it on `CMD_PUSH`, raises `CMD_DONE`/`CMD_ERROR` |
| Scheduler | `rtl/scheduler/` | Pops queued commands and dispatches each to the DMA Engine or Matrix Engine (V1: sequential, one command runs to completion before the next starts) |
| DMA Engine | `rtl/dma/` | Descriptor-based mover between DDR (AXI4 master) and the on-chip scratchpad, single channel |
| Local SRAM | `rtl/sram/` | Dual-port 64 KB scratchpad (4096 x 128b rows); fully verified standalone, available for V2+ multi-consumer scheduling |
| Matrix Compute Engine | `rtl/matrix_engine/` | Weight-stationary 16x16 systolic array (256 INT8 MACs), `C = A x B + C` over tiles up to 256 in M/K/N, INT32 saturating accumulator |
| Performance Monitor Unit | `rtl/pmu/` | Free-running counters -- cycle count, MAC-active/DMA-wait/scheduler-stall/idle cycles, last-command latency |
| Debug | `rtl/debug/` | Command trace buffer (opcode/tag/status per completed command) plus latched last-error code/tag |

**Numeric format**: INT8 operands (`OPERAND_WIDTH`), INT32 accumulator
(`ACCUM_WIDTH`), both defined in `rtl/include/tpe_pkg.sv` alongside every
other architectural parameter.

**Software command flow** (host's-eye view of one matmul):
```
1. Host DMA's weights:      stage CMD_LOAD_WEIGHT + addrs -> CMD_PUSH
2. Host DMA's activations:  stage CMD_LOAD_ACT + addrs    -> CMD_PUSH
3. Host issues matmul:      stage CMD_MATMUL + dims        -> CMD_PUSH
4. Host stores result:      stage CMD_STORE + addrs         -> CMD_PUSH
5. Host waits for CMD_DONE interrupt (or polls CP_STATUS.BUSY)
```
Verified end-to-end over the real AXI4-Lite MMIO interface in
`verif/cocotb_tb/top/test_top.py`'s `matmul_flow_test` -- no backdoor RTL
access except to the external DDR model.

Full detail (register map, exact interface widths, AXI4-Lite host-MMIO
router, V1 simplifications and why) is in
[`docs/architecture/tpe_architecture_spec.md`](docs/architecture/tpe_architecture_spec.md);
V2+ scope (activation unit, quantization, multi-channel DMA, improved
scheduler) is in that doc's
[Roadmap](docs/architecture/tpe_architecture_spec.md#6-roadmap).

## Toolchain

All open source, installed via Homebrew/pip:

| Tool | Version (this env) | Role |
|---|---|---|
| [Verilator](https://www.veripool.org/verilator/) | 5.050 | Primary simulator (RTL -> C++), coverage, assertions |
| [Icarus Verilog](http://iverilog.icarus.com/) | 13.0 | Secondary/cross-check simulator |
| [GTKWave](https://gtkwave.sourceforge.net/) | 3.3.107 | Waveform viewer |
| [cocotb](https://www.cocotb.org/) | 1.9.2 | Python testbench driver on top of the simulator |
| [pyuvm](https://pyuvm.readthedocs.io/) | 4.0.1 | Open-source, Python, class-based UVM-equivalent methodology |
| [cocotb-coverage](https://github.com/mciepluc/cocotb-coverage) | 1.2.0 | Testbench-side functional/cross coverage |

Install (macOS/Homebrew):
```
brew install verilator gtkwave
make venv        # creates .venv/, installs cocotb/pyuvm/cocotb-coverage/etc from tools/requirements.txt
```

Note: [Verible](https://github.com/chipsalliance/verible) was planned as
the SV linter/formatter but is no longer distributed via Homebrew in this
environment; `verilator --lint-only` is used instead (see
[Linting](#linting) below).

## Getting started

```
make venv       # set up the Python virtualenv
make regmap     # generate SV/C++/Markdown from the register map YAML
make model      # build the C++ golden-model CLI + run its unit tests
make lint       # lint all RTL
make sanity     # ~6 tests, one golden-path test per block -- proves the chain works
```

`make help` lists every available target.

## Verification & testing

Methodology in full: [`docs/verification/test_plan.md`](docs/verification/test_plan.md)
(per-tier sizing, coverage goals, bug-injection policy) and
[`docs/verification/coverage_plan.md`](docs/verification/coverage_plan.md)
(how coverage is modeled). Day-to-day usage in full:
[`docs/flows/regression_flow.md`](docs/flows/regression_flow.md) and
[`docs/flows/build_flow.md`](docs/flows/build_flow.md).

### Linting
```
make lint                 # tools/lint.py -- every rtl/ block, source list + waivers in one place
```

### Running a single test
Every block has its own cocotb testbench under `verif/cocotb_tb/<block>/`.
Run one test directly while developing/debugging:
```
TESTCASE=matmul_sanity_test make -C verif/cocotb_tb/matrix_engine
TESTCASE=dma_random_test TPE_SEED=12345 make -C verif/cocotb_tb/dma   # reproducible seed
make -C verif/cocotb_tb/<block> waves                                  # open the last run in GTKWave
```
The full test catalog (every test, tagged sanity/directed/random/error/
integration) is [`verif/testlists/standalone.yaml`](verif/testlists/standalone.yaml).
Or per-block shortcuts from the top level: `make sim-sram`,
`make sim-matrix-engine`, `make sim-dma`, `make sim-top`, `make sim-pmu`,
`make sim-debug`.

### Regression tiers
```
make sanity     # ~6 tests, seconds       -- one golden-path test per block
make smoke      # ~18 tests, ~1 min       -- cross-block + directed error/boundary paths
make daily      # 100 tests, ~2 min       -- directed + seeded-random, tools/gen_tests.py-generated
make random     # 100 tests, ~2 min       -- pure seeded-random sweep
```
All four run through `tools/regression.py` (the local parallel job-
scheduler / farm replacement -- jobs run across block directories, JUnit
XML + JSON results written to `sim/logs/<suite>/`). **Some `FAIL`s are
expected** on `smoke`/`daily`/`random`: this repo ships 10 intentionally
injected bugs (see [Bug catalog](#bug-catalog-intentional-bugs) below) and
the tests are supposed to catch them -- the run's exit code only goes
nonzero on an actual infrastructure error (`ERROR`/`TIMEOUT`), never on a
catalogued `FAIL`. Reproduce any specific failure bit-for-bit with the
`TESTCASE=... TPE_SEED=...` form above.

### Coverage
```
make cov-merge SUITE=smoke     # tools/cov_merge.py -- merges coverage.dat via verilator_coverage,
                                 # plus TB-side cocotb-coverage XML where sampled
```
Writes `sim/logs/<suite>/merged_coverage.dat` and a text summary
(line/toggle/branch, plus every RTL-side functional/FSM SystemVerilog
covergroup).

### Profiling
```
make profile SUITE=daily       # tools/profiler.py -- slowest tests + per-directory outlier flags
```

### Waveforms
```
python3 tools/waves.py dma     # opens that block's last sim's dump.vcd in GTKWave
```

### Bug catalog (intentional bugs)
The RTL contains 7 deliberately injected bugs (starting at the Matrix
Compute Engine) so the verification environment has something real to
catch, plus 3 golden-model/testbench integration bugs added specifically so
a test's failure *type* -- not just its message -- tells you which category
caught it: a plain `assert` (`AssertionError`) for most scoreboard data
compares, a distinct `MismatchError` for one that's deliberately kept
separate, a status/register check using `pyuvm.uvm_error()`/`uvm_fatal()`
(`UVMError`/`UVMFatalError`), and the C++ golden model itself failing
outright raising `CModelError`. Each is documented with file:line, root
cause, symptom, and exactly which test catches it in
[`docs/verification/bug_list.md`](docs/verification/bug_list.md). The
build/regression *infrastructure* is expected to run cleanly end-to-end at
all times; a test **failing** because of a catalogued bug is the intended
outcome, not a broken repo -- and a regression with *fewer* failures than
expected is itself the red flag (it means a bug got accidentally fixed, or
a test stopped exercising it).

## Repository layout

```
docs/            architecture spec, register map (YAML source of truth + generated),
                 verification test plan / coverage plan / bug catalog, flow docs
rtl/             synthesizable SystemVerilog, one directory per block
model/           C++17 golden reference model (OOP, mirrors the RTL block structure)
verif/           cocotb+pyuvm testbenches, SVA (bind files), coverage models, testlists
tools/           Python infra: register-map generator, test generator, regression/
                 job-scheduler, coverage merger, profiler, linter, waves launcher, logger
sim/             simulation build/run outputs (gitignored except .gitkeep)
.github/         GitHub Actions workflows -- lint-smoke/daily-regression/random-regression.yml
                 (the CI actually running on this repo)
ci/              reference Jenkinsfile (ci/jenkins/) -- not what GitHub Actions runs
Makefile         top-level entry point; wraps everything above
run_sim          unified test orchestrator (alongside Makefile, see docs/flows/run_sim_flow.md)
```

## Documentation index

- [Handbook](docs/HANDBOOK.md) -- every command in this project's flow, one line each
- [Architecture spec](docs/architecture/tpe_architecture_spec.md) -- blocks, interfaces, parameters
- [Register map](docs/register_map/generated/register_map.md) (generated -- edit [`tpe_regs.yaml`](docs/register_map/tpe_regs.yaml) instead)
- [Verification test plan](docs/verification/test_plan.md)
- [Coverage plan](docs/verification/coverage_plan.md)
- [Bug catalog](docs/verification/bug_list.md) -- intentionally injected RTL bugs and what catches them
- [Build flow](docs/flows/build_flow.md)
- [Regression flow](docs/flows/regression_flow.md)
- [run_sim flow](docs/flows/run_sim_flow.md) -- unified test orchestrator (options reference + examples)
- [CI/CD flow](docs/flows/ci_flow.md) -- see also the [live GitHub Actions runs](https://github.com/bhavanibedreshankar/tpe-tensor-processing-engine/actions)
