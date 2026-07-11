# TPE -- Tensor Processing Engine

A from-scratch, production-flow-style ASIC/RTL project: a small TPU-like
matrix-multiply accelerator plus a full open-source verification
environment (C++ golden model, pyuvm/cocotb testbenches, SVA assertions,
functional+structural+FSM coverage, Make-based build system, Python
regression/orchestration tooling, CI). See [`overview`](overview) for the
original product vision and [`docs/architecture/tpe_architecture_spec.md`](docs/architecture/tpe_architecture_spec.md)
for the RTL-facing spec this repo actually implements.

**Everything here uses only free/open-source tools** -- no paid EDA
licenses. See [Toolchain](#toolchain) below.

## Status

Building incrementally, foundation first. Current state:

| Milestone | Scope | Status |
|---|---|---|
| M0 | Foundation: repo skeleton, toolchain smoke test, shared RTL package + common lib, register map + generators, docs, build system | **done** |
| M1 | Local SRAM scratchpad + reusable pyuvm verification pattern | **done** |
| M2 | Matrix Compute Engine (systolic MAC array, GEMM) | **done** (3 intentional bugs present, see bug catalog) |
| M3 | DMA Engine (AXI4, descriptor-based) | **done** (1 intentional bug present, see bug catalog) |
| M4 | Command Processor + Scheduler + top-level integration | **done** (2 intentional bugs present, see bug catalog) |
| M5 | Performance Monitor Unit + Debug infrastructure | **done** (1 intentional bug present, see bug catalog) |
| M6 | Regression infrastructure (test generator, job scheduler, coverage merge, profiler, lint, CI) | **done** |
| M7 | Bug catalog + full regression proof | not started |

RTL is complete for V1 (M1-M5); M6 built the regression/CI tooling around
it. This README is updated as each milestone completes.

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
environment; `verilator --lint-only` is used instead (see `make lint`).

## Quick start

```
make venv              # set up the Python virtualenv
make regmap             # generate SV/C++/Markdown from the register map YAML
make lint                # lint all RTL (tools/lint.py)
make toolchain-smoke     # prove cocotb+pyuvm+Verilator+coverage+waveform all work
make sanity              # ~6 tests, one golden-path test per block
make smoke               # ~18 tests, cross-block + directed error/boundary paths
make daily               # 100 tests: directed + seeded-random
make random              # 100 seeded-random tests
```

`make help` lists every available target. See
[Regression flow](docs/flows/regression_flow.md) for what a "clean" run
looks like (some `FAIL`s are expected -- they're the catalogued bugs, see
below) and how to reproduce/profile/merge-coverage for any run.

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
ci/              GitHub Actions workflow + reference Jenkinsfile
Makefile         top-level entry point; wraps everything above
```

## Documentation index

- [Architecture spec](docs/architecture/tpe_architecture_spec.md) -- blocks, interfaces, parameters
- [Register map](docs/register_map/generated/register_map.md) (generated -- edit [`tpe_regs.yaml`](docs/register_map/tpe_regs.yaml) instead)
- [Verification test plan](docs/verification/test_plan.md)
- [Coverage plan](docs/verification/coverage_plan.md)
- [Bug catalog](docs/verification/bug_list.md) -- intentionally injected RTL bugs and what catches them
- [Build flow](docs/flows/build_flow.md)
- [Regression flow](docs/flows/regression_flow.md)
- [CI/CD flow](docs/flows/ci_flow.md)

## Design note: intentional bugs

Per the project's original goals, the RTL in this repo contains
deliberately injected bugs (starting at M2) so the verification environment
has something real to catch. The build/regression *infrastructure* is
expected to run cleanly end-to-end at all times; specific test **results**
failing because of a real, catalogued bug is the intended outcome, not a
broken repo. See [`docs/verification/bug_list.md`](docs/verification/bug_list.md).
