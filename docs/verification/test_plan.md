# TPE Verification Test Plan

Status: living document, grown alongside the RTL milestones (see the top
project README for milestone status). This plan covers **V1** scope only:
Command Processor, Scheduler, DMA Engine, Local SRAM, Matrix Compute Engine,
PMU, Debug infrastructure.

## 1. Methodology

- **Testbench**: [cocotb](https://www.cocotb.org/) driving the DUT under
  [Verilator](https://www.veripool.org/verilator/) (primary) or
  [Icarus Verilog](http://iverilog.icarus.com/) (secondary cross-check),
  structured with [pyuvm](https://pyuvm.readthedocs.io/) -- an open-source,
  Python, class-based reimplementation of the UVM methodology (agents,
  drivers, monitors, sequencers, sequences, scoreboards, the factory, phased
  `build_phase`/`connect_phase`/`run_phase`/`report_phase`). One shared base
  environment lives in `verif/cocotb_tb/env/` and every block/top-level
  environment subclasses it -- this is what "OOP/modular verification" means
  concretely in this repo.
- **Golden model**: a C++17 reference model (`model/`) mirroring the RTL's
  class structure (`Scratchpad`, `MacArray`, `Accumulator`, `DmaEngine`,
  `CommandProcessor`). Built as the `tpe_model` CLI; a pyuvm scoreboard
  invokes it once per test with the same command/descriptor stream the RTL
  executed, and diffs final SRAM/register state against what the RTL
  monitor observed.
- **Assertions**: SystemVerilog Assertions (SVA), both immediate
  (`assert (...)`) and concurrent (`assert property (...)`), written per
  block under `verif/sva/` and bound into the DUT via `bind` so the
  synthesizable RTL itself stays assertion-free. Checked live by the
  simulator every run (`--assert` in the Verilator build).
- **Coverage** (two complementary kinds, merged by `tools/cov_merge.py`):
  - *Structural*: line/toggle/branch coverage from Verilator
    (`--coverage-line --coverage-toggle`), NOT the blanket `--coverage` flag
    -- see the note in `verif/cocotb_tb/smoke/Makefile` about a Verilator
    5.050 compiler bug that combination triggers.
  - *Functional/FSM*: SystemVerilog covergroups (`--coverage-user`) for
    RTL-side cross/bin coverage (e.g. tile-size x saturation crosses), plus
    `cocotb-coverage` `CoverPoint`/`CoverCross` for testbench-side stimulus
    coverage (e.g. which opcodes/error paths a regression actually
    exercised). FSM coverage specifically targets the Scheduler and Command
    Processor control FSMs (state + arc coverage).
- **Logging**: `tools/common/logger.py` gives every test a structured,
  leveled, colorized console stream plus a per-test log file under
  `sim/logs/<suite>/<test>.log`; `tools/regression.py` aggregates a
  top-level regression log and JUnit XML.

## 2. Test tiers

| Tier | Location | Purpose | Sizing |
|---|---|---|---|
| Standalone | `verif/testlists/standalone.yaml` | One directed test run by hand while developing/debugging a block | N/A, ad hoc |
| Sanity | `verif/testlists/sanity.yaml` | Fast golden-path check per block, run after every RTL edit | ~1 test/block |
| Smoke | `verif/testlists/smoke.yaml` | Cross-block golden-path + a few directed error-path tests, sized for pre-commit | ~10-20 tests |
| Daily | `verif/testlists/daily.yaml` | Directed + seeded-random mix targeting broad functional/code coverage | 100 tests |
| Random | `verif/testlists/random.yaml` | Fully constrained-random, seed-logged for reproducibility, targeting corner cases the directed tests miss | 100 tests |

All tiers run through `tools/regression.py` (the local job-scheduler/farm
replacement) or `make sanity|smoke|daily|random`.

## 3. Per-block test plan

Each block's detailed test list (directed scenarios, expected coverage
bins, and which of the block's SVA the tests are expected to hit) is
maintained next to its testbench in `verif/cocotb_tb/<block>/README.md`,
added as that block's milestone lands. This section tracks the
cross-cutting scenarios that only make sense at integration level.

### 3.1 End-to-end (top-level, M4)
- Load weights -> load activations -> matmul -> store -> completion IRQ
  (the vision doc's canonical example, minus activation function -- V2).
- Back-to-back commands with the scheduler overlapping DMA of tile N+1 with
  compute of tile N.
- Error injection: bad opcode, out-of-range SRAM address, dimension that
  exceeds `MAX_TILE_DIM` -- confirm `CMD_ERROR` + `ERROR_CODE`/`ERROR_TAG`
  latch correctly and the command FIFO recovers (next command still runs).

### 3.2 Reset / power-on
- Register reset values match `docs/register_map/tpe_regs.yaml` exactly
  (a generated test iterates the whole register map -- see
  `tools/regmap_gen.py` output consumed by `verif/cocotb_tb/env/`).
- Mid-operation soft reset (`CP_CTRL.SOFT_RESET`) leaves the design in a
  clean, re-startable state (no stuck FIFOs, no latched errors).

## 4. Coverage goals (V1 exit criteria)

- 100% line coverage on all `rtl/*/` blocks except `rtl/top/` glue
  (waived instances documented in `tools/lint.py`'s waiver list if any
  remain unreachable, e.g. defensive default cases).
- >=90% toggle coverage on primary datapath signals (operand/accumulator
  buses, SRAM data bus, AXI data bus).
- 100% of defined functional covergroup bins hit across the daily+random
  regressions combined (bins are enumerated per-block as each testbench
  lands).
- 100% FSM state coverage and >=90% FSM arc coverage on the Scheduler and
  Command Processor control FSMs.
- Every intentionally injected bug (see
  [`bug_list.md`](bug_list.md)) has at least one test that fails because of
  it, and that failure is traceable to a specific assertion or scoreboard
  mismatch, not a vague timeout.

## 5. Bug-injection policy

RTL bugs are injected deliberately (see [`bug_list.md`](bug_list.md)) to
prove the verification environment actually catches defects rather than
rubber-stamping a design that happens to be correct. The *infrastructure*
(build, lint, sim, regression running, report generation, coverage merge)
must always complete successfully; individual test **results** are allowed
-- expected -- to show FAILs pointing at the injected bugs. A regression run
with zero failures on the bug-hunting-relevant tests would itself be a red
flag (it would mean either the bug was accidentally fixed or the test
doesn't actually exercise it), so `tools/regression.py` reports are read
against `bug_list.md`, not against a blanket "all green" expectation.

## 6. Open items / not yet covered

Tracked here so nothing silently falls through the cracks as milestones
land; each is removed once its milestone's section above is filled in.

- [x] Local SRAM detailed test list (M1) -- see `verif/cocotb_tb/sram/README.md`
- [x] Matrix Compute Engine detailed test list (M2) -- see `verif/cocotb_tb/matrix_engine/README.md`
- [ ] DMA Engine detailed test list (M3)
- [ ] Command Processor / Scheduler detailed test list (M4)
- [ ] PMU / Debug detailed test list (M5)
- [ ] Coverage closure report template (M6)
