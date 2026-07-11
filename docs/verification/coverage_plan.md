# TPE Coverage Plan

Companion to [`test_plan.md`](test_plan.md) section 4 (coverage goals/exit
criteria). This document defines *how* coverage is modeled and measured, and
is the place each block's covergroup/coverpoint bins get enumerated as they
land.

## 1. Coverage kinds and tooling

| Kind | Tool | Flag(s) | Merged by |
|---|---|---|---|
| Line | Verilator | `--coverage-line` | `verilator_coverage --write` via `tools/cov_merge.py` |
| Toggle | Verilator | `--coverage-toggle` | same |
| Branch | Verilator | (bundled with line coverage) | same |
| Functional (RTL-side covergroups) | Verilator | `--coverage-user` | same `coverage.dat`, annotated with `verilator_coverage -annotate` |
| Functional/cross (testbench-side) | `cocotb-coverage` (`CoverPoint`/`CoverCross`) | N/A (Python) | `tools/cov_merge.py` reads each test's exported coverage DB and sums bins |
| FSM state/arc | SV covergroup on the block's state register (RTL-side) | `--coverage-user` | same as functional |

**Do not pass Verilator's blanket `--coverage` flag** -- combined with a
concurrent SVA assertion using `|=>` or `disable iff`, Verilator 5.050 hits
an internal compiler bug (`V3Localize.cpp:203, AstVarRef not under
function`). Always request the three kinds explicitly
(`--coverage-line --coverage-toggle --coverage-user`), which is functionally
equivalent and does not trigger the bug. See
`verif/cocotb_tb/smoke/Makefile` for the reference invocation.

## 2. Bin naming convention

`<block>.<coverpoint>.<bin>`, e.g. `matrix_engine.tile_dim_m.boundary_max`.
Cross coverage bins concatenate with `x`:
`matrix_engine.tile_dim_m x saturation.hit`. This keeps merged reports
greppable and lets `tools/cov_merge.py` produce a per-block rollup without
parsing tool-specific naming.

## 3. Per-block coverage models

Filled in as each block's testbench lands (mirrors the milestone order in
the top-level plan/README).

### 3.1 Local SRAM (M1)

RTL-side (`verif/coverage/sram_cov.sv`, bound to `dp_ram`), per port:
`cp_op` (idle/read/write), `cp_addr_region` (low/mid/high thirds),
`cp_strb` (zero/full/partial, port A only), `cx_op_addr` (op x region
cross). TB-side (`verif/cocotb_tb/sram/coverage.py`, cocotb-coverage):
`sram.port_{a,b}.op_type`, `sram.port_{a,b}.addr_region`, and their cross
-- deliberately mirrors the RTL-side bins so a gap in one is a signal to
check the other, not just a documentation exercise. `sram_random_test`'s
two disjoint address ranges are wide enough that the low/mid/high thirds
each get hit on both ports.

### 3.2 Matrix Compute Engine (M2)

RTL-side (`verif/coverage/matrix_engine_cov.sv`, bound to
`matrix_engine_ctrl`): `cp_state`/`cp_arc` -- explicit FSM state and
transition coverage over the 5-state control FSM (IDLE/LOAD_WEIGHTS/
COMPUTE/DRAIN/DONE), satisfying the "FSM coverage" requirement directly
against the RTL's own state encoding rather than a Python
reimplementation; `cp_dim_k`/`cp_dim_n`/`cp_dim_m` -- tile-size bins
(one/mid/max for k and n, narrow/wide for m) sampled on `start`;
`cp_overflow_sticky` -- did this run see a saturating accumulation.
SVA (`verif/sva/matrix_engine_sva.sv`): done pulses exactly one cycle,
weight_load_row is one-hot0, start-time dims are in range, and
`mac_array`'s result is never X when valid.

### 3.3 DMA Engine (M3)

RTL-side (`verif/coverage/dma_cov.sv`, bound to `tpe_dma`): `cp_state`/
`cp_arc` -- FSM state and transition coverage over the 10-state control FSM
including the multi-burst continuation arcs (`RD_DATA -> DECODE`,
`WR_RESP -> DECODE`) that the intentional bug (#4 in the bug catalog) lives
in; `cp_dir`/`cp_len_rows` -- direction and transfer-size bins (one row,
sub-burst, exact-burst, multi-burst) sampled on `start`; `cp_burst_full` --
did this run ever issue a full `MAX_BURST_BEATS`-beat burst. SVA
(`verif/sva/dma_sva.sv`): standard AXI4 VALID-stability on both the
`tpe_dma` master side and the `axi4_ddr_model` slave side, `done`/`error`
mutual exclusion, and no-X on `rdata` when valid.

### 3.4 Command Processor / Scheduler (M4)
_TBD when M4 lands._

### 3.5 PMU / Debug (M5)
_TBD when M5 lands._

## 4. Coverage closure process

1. `tools/regression.py` runs a suite; each test's simulator invocation
   writes its own `coverage.dat` (Verilator) and `.cocotb_coverage` DB
   (cocotb-coverage) under `sim/logs/<suite>/<test>/`.
2. `tools/cov_merge.py --suite <name>` merges all of those into
   `sim/logs/<suite>/merged_coverage.dat` (Verilator side) and a summed
   Python coverage-DB (functional side), then renders a single HTML/text
   summary.
3. Gaps are triaged: either add a directed test (`verif/testlists/`), add a
   random-generator constraint (`tools/gen_tests.py`), or -- rarely -- waive
   a genuinely unreachable bin with a documented reason in the block's
   section above.
