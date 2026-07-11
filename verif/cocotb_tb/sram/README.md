# Local SRAM testbench

The first real block testbench, establishing the reusable pyuvm pattern in
`verif/cocotb_tb/env/` (`SyncPortItem`/`SyncPortDriver`/`SyncPortMonitor`/
`SyncPortAgent`, `TpeBaseTest`, `golden_model.run_tpe_model`) that later
blocks (DMA and Matrix Engine, wherever they touch a dp_ram-style SRAM port)
reuse directly instead of re-deriving driver/monitor bus wiggling.

## Tests

- `sram_sanity_test` -- directed golden path: a handful of writes to
  reserved addresses 4090-4095, read back on the same port.
- `sram_random_test` -- constrained-random writes/reads on both ports
  concurrently (disjoint address ranges to sidestep the documented
  same-cycle cross-port write hazard), 150 ops/port, seeded for
  reproducibility.

Both tests check two independent things:
1. **Live, per-cycle**: a Python shadow memory in `scoreboard.py` predicts
   every read's `rdata` and is updated by every write, checked cycle by
   cycle as the monitor reports each operation.
2. **Final, whole-image**: at `report_phase`, every write observed during
   the test is replayed through the real C++ golden model
   (`model/build/tpe_model sram-apply`) and the resulting image is diffed
   byte-for-byte against the shadow memory -- proving the file-based
   golden-model integration pattern (see `model/README.md`) before M2 needs
   it for actual GEMM compute, where a parallel Python reimplementation of
   the math won't be feasible.

Run:
```
make -C model            # build tpe_model first (or `make model` here)
make                      # runs both tests
make waves                # opens the VCD in GTKWave
```

## A monitor timing bug worth knowing about

Getting the live scoreboard to agree with the RTL took two fixes, both now
folded into the reusable `verif/cocotb_tb/env/` components (not
SRAM-specific, so every later block inherits the fix):

1. cocotb's `Clock` produces its first 0->1 transition at t=0, which counts
   as a valid `RisingEdge`. A driver racing ahead of a monitor at that very
   first edge can drive a second item before the monitor ever samples the
   first (see the settle-then-`Timer` sequence in `test_sram.py`'s
   `_start_clock`).
2. More fundamentally: `SyncPortDriver` retires the just-finished item and
   drives the *next* one within the same simulation delta as the
   `RisingEdge` it was waiting on -- before any `ReadOnly` callback can
   fire. A monitor sampling ctrl fields (en/we/addr/wdata) at that same
   `RisingEdge`+`ReadOnly` therefore captures the *next* operation's ctrl
   paired with the *current* operation's `rdata`. A scoreboard with no
   persistent state (predicting a counter's next value from its own
   last-observed value, say) self-corrects every cycle and never notices.
   A scoreboard maintaining independent persistent state -- a shadow
   memory, here -- silently drops one operation's effect for good. Fixed
   in `SyncPortMonitor` by sampling ctrl fields at `FallingEdge` (mid-cycle,
   unambiguous) and `rdata` at the following `RisingEdge`, so both fields
   always describe the same operation. See that file's docstring for the
   full derivation.

## `coverage.py`'s CoverCross bug (found via M6's `tools/cov_merge.py`)

`op_x_region`'s cross-coverage bins (op_type x addr_region) read 0% on
every run from M1 through M5, invisible until M6's coverage-merge tooling
actually rendered a report -- neither test's `report_phase` assertion
depends on cross-coverage percentages, so nothing failed. Root cause:
`CoverCross(...)` was a bare statement after both `@CoverPoint`-decorated
sampling functions, which registers the cross (so its bins count toward
the *size* used in coverage-percentage math, silently dragging every
reported percentage down) but never actually wraps `sample_port_a`/
`sample_port_b`, so its bins never increment. `CoverCross` must itself be
a decorator stacked on the sampling function -- and, since its `__init__`
looks up its constituent `CoverPoint`s in `coverage_db` immediately, it
must be the *innermost* decorator (closest to `def`), applied only after
those `CoverPoint`s already exist, matching cocotb-coverage's own
documented example. Fixed by moving both `CoverCross` calls to decorate
`sample_port_a`/`sample_port_b` directly, below their `CoverPoint`s.
