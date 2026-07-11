# Top-level (end-to-end) testbench

Verifies `rtl/top/tpe_top.sv` -- the real integration of everything built
in M1-M3 (`rtl/command_processor/tpe_cmd_proc.sv` +
`rtl/scheduler/tpe_scheduler.sv` + `rtl/dma/tpe_dma.sv` +
`rtl/matrix_engine/matrix_engine.sv`) behind the host-facing AXI4-Lite MMIO
interface, wired to a behavioral DDR (`verif/models/axi4_ddr_model.sv`) by
`top_test_harness.sv` (not RTL in its own right, see its header comment).
This is the first testbench that drives the chip **the way real driver
software would**: stage command registers, write `CMD_PUSH`, poll
`STATUS.BUSY` (or wait on `irq`), read results back -- no backdoor access
to internal RTL state at all except for preloading/inspecting the DDR
model (which stands in for something genuinely external to the chip).

See `rtl/top/tpe_top.sv`'s header comment for the V1 architecture decision
this milestone required: matrix_engine's four internal buffers serve
directly as the addressable "Local SRAM" for V1's matmul-only flow (no
separate shared `tpe_sram` instance in this integration -- that block
remains a fully verified, reusable standalone piece for a future
multi-consumer scheduler to wire in), and why storing results needs a
small chunk-address adapter (out_buf's row is 4x wider than one AXI beat
at the default 16x16 array size).

## Tests

- `matmul_flow_test` -- the overview's canonical command sequence: load
  weights, load activations, matmul, store result (no activation unit --
  that's V2), driven entirely over AXI4-Lite, checked against the same C++
  golden model M2 uses (reused, not reimplemented -- see `scoreboard.py`).
- `irq_test` -- `CMD_IRQ_TEST` asserts `irq`, `IRQ_STATUS.CMD_DONE` reads
  back set, write-1-to-clear deasserts `irq`.
- `error_handling_test` -- `CMD_NOP`/`CMD_BARRIER` (immediate complete, no
  engine dispatch), an unrecognized opcode (`STAT_BAD_OPCODE`), and
  `dim_k > ROWS` (`STAT_BAD_DIM`).
- `matmul_full_width_test` -- directed: `dim_n == COLS` exactly (the
  array's full width, not an out-of-range value).
- `irq_independent_clear_test` -- directed: force both `CMD_DONE` and
  `CMD_ERROR` set, clear only `CMD_ERROR`, check `CMD_DONE` survives.

Run:
```
make -C model               # build tpe_model first (or `make model` here)
make                         # runs all five tests
make waves
```

## Status: 2 intentional bugs present (see docs/verification/bug_list.md)

`matmul_flow_test`, `irq_test`, and `error_handling_test` pass;
`matmul_full_width_test` and `irq_independent_clear_test` **fail by
design**:

```
matmul_full_width_test: MATMUL with dim_n==COLS(16) status=2, want STAT_OK
irq_independent_clear_test: clearing CMD_ERROR alone should leave CMD_DONE
  set: got 0x3, want 0b01
```

Both bugs were specifically chosen not to be hit by `matmul_flow_test`
(which uses `dim_n=5 < COLS` and only ever clears `CMD_DONE` alone) --
each needed its own directed test, same lesson as M3's
`dma_multiburst_write_test`.

## Bringing this up

Both real (non-intentional) bugs found here were cocotb usage mistakes,
not RTL bugs -- worth knowing before writing an AXI4-Lite driver for any
future block:

1. **Writing a signal immediately after `await ReadOnly()`** raises
   `Exception: Write ... scheduled during a read-only sync phase`. Fixed
   `verif/cocotb_tb/env/axi4_lite_driver.py` to sample with a plain
   post-`RisingEdge` read instead (no `ReadOnly()`), matching the pattern
   already used throughout `test_dma.py`/`test_matrix_engine.py`.
2. The register map's Python bindings (`verif/cocotb_tb/env/tpe_regs.py`)
   are generated from the same YAML as the SV package and C++ header (see
   `tools/regmap_gen.py`) -- there is no hand-maintained third copy of
   register addresses to drift out of sync.
