# verif/ -- verification environment

| Directory | Contents | Status |
|---|---|---|
| `cocotb_tb/smoke/` | Toolchain smoke test (throwaway DUT) | done, see its own README |
| `cocotb_tb/env/` | Reusable pyuvm classes: `SyncPortItem/Driver/Monitor/Agent`, `RowCollector`, `Axi4LiteDriver`, `TpeBaseTest`, `golden_model.run_tpe_model`, generated `tpe_regs.py` | done (M1, extended M3/M4) |
| `cocotb_tb/sram/` | Local SRAM testbench -- see its own README, including a subtle monitor-timing bug worth reading before writing the next block's TB | done (M1) |
| `cocotb_tb/matrix_engine/` | Matrix Compute Engine testbench (systolic GEMM) -- see its own README for the timing derivation and 3 intentional bugs it catches | done (M2) |
| `cocotb_tb/dma/` | DMA Engine testbench (AXI4 master vs. behavioral DDR model + real SRAM) -- see its own README | done (M3) |
| `cocotb_tb/top/` | End-to-end testbench driving the real AXI4-Lite host MMIO interface -- see its own README | done (M4, extended M5) |
| `cocotb_tb/pmu/` | PMU testbench (register pokes + direct event-input driving, no pyuvm env needed) -- see its own README | done (M5) |
| `cocotb_tb/debug/` | Debug infrastructure testbench (trace FIFO + error latch) -- see its own README | done (M5) |
| `models/` | Verification-only behavioral models that aren't the DUT (e.g. `axi4_ddr_model.sv`) -- distinct from `rtl/` (synthesizable) | done (M3) |
| `cocotb_tb/<block>/` | Per-block pyuvm environment + sequences | added per block's milestone |
| `sva/` | SystemVerilog Assertions, bound into the DUT via `bind` (not embedded in `rtl/`); `sram_sva.sv`, `matrix_engine_sva.sv`, `dma_sva.sv`, `cmd_proc_sva.sv`, `pmu_sva.sv`, `debug_sva.sv` done | added per block's milestone |
| `coverage/` | Functional/cross/FSM covergroups; `sram_cov.sv`, `matrix_engine_cov.sv`, `dma_cov.sv`, `cmd_proc_cov.sv`, `pmu_cov.sv`, `debug_cov.sv` (incl. FSM state/arc coverage) done | added per block's milestone |
| `testlists/` | `standalone.yaml`/`sanity.yaml`/`smoke.yaml`/`daily.yaml`/`random.yaml` -- test tier definitions consumed by `tools/regression.py` | added in M6 |

See [`docs/verification/test_plan.md`](../docs/verification/test_plan.md)
for methodology and per-tier sizing, and
[`docs/verification/coverage_plan.md`](../docs/verification/coverage_plan.md)
for how coverage is modeled and merged.
