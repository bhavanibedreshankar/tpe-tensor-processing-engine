# TPE Intentional Bug Catalog

This repo's RTL contains deliberately injected bugs, added block-by-block as
each milestone lands, to prove the verification environment (assertions,
scoreboard, coverage) actually catches real defects. Each entry below is
filled in when its bug is injected -- **not before** -- so this file always
reflects the true current state of the RTL, not a forward-looking plan.

Columns: which test(s) are expected to fail, what the observable symptom is
(assertion fire / scoreboard mismatch / coverage gap), and root cause.

## Status

7 bugs injected: 3 in the Matrix Compute Engine (M2), 1 in the DMA Engine
(M3), 2 in the Command Processor/Scheduler (M4), 1 in the PMU (M5). Each was
chosen deliberately so the relevant block's sanity/golden-path test stays
green -- they only surface on narrower/nonzero/multi-burst/boundary/
overflow/timing-sensitive paths that random and directed edge-case tests
exercise, exactly as a real regression suite would catch them (a passing
smoke test does not mean a clean design).

| # | Block | File:Line | Symptom | Root cause | Caught by |
|---|---|---|---|---|---|
| 1 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:154,166` | Wrong GEMM values whenever `dim_k < ROWS`; row `k_q` (one past the intended last row) spuriously contributes to the sum. Never fires when `dim_k == ROWS` (the array's full physical width), so a naive full-width smoke test would never catch it. | Off-by-one in the row-contribution gate: `(r <= k_q)` should be `(r < k_q)` (row indices are 0-based, so row index `k_q` is one past the last valid row `k_q-1`). | `matmul_random_test` (several iterations use `dim_k < ROWS`) |
| 2 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:193` | Wrong GEMM values in output columns >= 2 whenever C_in (the accumulator seed) is nonzero. Invisible when C_in is all-zero (sanity test), since adding a *misaligned* zero is still zero. | Off-by-one tap selection in the per-column seed skew chain: columns `c >= 2` read `seed_chain[c-2]` instead of `seed_chain[c-1]`, feeding the seed value that was actually meant for `m-1` (one row of C_in too early) into column c's accumulation for the current m. | `matmul_random_test` (nonzero C_in, `dim_n >= 3`) |
| 3 | matrix_engine | `rtl/matrix_engine/pe.sv:50` | Negative accumulator overflow silently wraps (two's-complement) instead of saturating to `INT32_MIN`, while positive overflow still saturates correctly. `overflow_sticky` still correctly reports that an overflow happened either way (detection and clamping are separate logic) -- only the clamped *value* is wrong, which is exactly why checking both the value and the status flag independently matters. | Asymmetric ternary: `acc_in[MSB] ? sum : AccumMax` should be `acc_in[MSB] ? AccumMin : AccumMax` -- the negative-overflow branch returns the unclamped wrapped `sum` instead of `AccumMin`. | `matmul_overflow_test` (`overflow_neg` case specifically; `overflow_pos` stays green) |
| 4 | dma | `rtl/dma/tpe_dma.sv:161` | SRAM->DDR transfers whose length leaves exactly 1 beat for a trailing burst (e.g. 17 rows = one 16-beat burst + one 1-beat burst) silently drop that final row -- it's never written to DDR. Only affects the write (SRAM->DDR) direction; only affects transfers where `n_rows % MAX_BURST_BEATS == 1`. **The seeded `dma_random_test` in this repo happens not to roll that exact case** -- only the directed `dma_multiburst_write_test` (17 rows, SRAM->DDR) catches it reliably, which is itself worth noting: a green random regression is not proof of a clean design. | Off-by-one in the burst-continuation check: `beats_remaining_q <= BeatsWidth'(1)` should be `beats_remaining_q == BeatsWidth'(0)` -- at this point in the FSM all of the just-completed burst's beats are already accounted for, so "1 remaining" means one more (small) burst is still needed, not that the transfer is done. | `dma_multiburst_write_test` |
| 5 | scheduler | `rtl/scheduler/tpe_scheduler.sv:84` | `CMD_MATMUL` with `dim_n == COLS` (the array's full physical width -- a legitimate, exactly-fitting tile, not an out-of-range one) is wrongly rejected with `STAT_BAD_DIM` instead of dispatched. `matmul_flow_test` uses `dim_n=5 < COLS`, so it never hits this boundary. | Off-by-one in the bounds check: `cmd_q.dim_n < TILE_DIM_WIDTH'(COLS)` should be `<=` -- `dim_n == COLS` means "use all COLS columns," which is in range, not one past it. | `matmul_full_width_test` (directed `dim_n == COLS`) |
| 6 | cmd_proc | `rtl/command_processor/tpe_cmd_proc.sv:242` | Writing 1 to `IRQ_STATUS.CMD_ERROR` (bit 1) alone does nothing -- the bit never clears unless `CMD_DONE` (bit 0) is *also* being written 1 in the same access, and doing so clears both regardless of which the host intended. | Copy-paste-shaped bit-width bug: the write-1-to-clear mask is built from `s_wdata[0]` broadcast to both bits (`~{2{s_wdata[0]}}`) instead of using each bit's own `s_wdata` value (`~s_wdata[1:0]`). | `irq_independent_clear_test` (forces both bits set, clears `CMD_ERROR` alone, checks `CMD_DONE` survives) |
| 7 | pmu | `rtl/pmu/tpe_pmu.sv` (the `if (cmd_done_valid)` branch capturing `cmd_latency_last_q`) | `PMU_CMD_LATENCY_LAST` reads exactly 1 cycle lower than the command's true dispatch-to-completion cycle count, every time, for every command. Invisible to any test that doesn't independently hand-derive the expected cycle count (which is why this is a PMU-only bug: `pmu_debug_integration_test` in the top-level suite only checks `CYCLE_COUNT > 0`, not an exact latency value). | Same-cycle nonblocking-assignment ordering: on the `cmd_done_valid` cycle, `latency_ctr_q`'s own completion-cycle increment (`latency_ctr_q <= latency_ctr_q + 1`) and `cmd_latency_last_q`'s capture (`cmd_latency_last_q <= latency_ctr_q`) both read the *old* (pre-increment) value of `latency_ctr_q` in the same cycle -- the capture should read `latency_ctr_q + 32'd1` to include the completion cycle itself. | `latency_test` (drives a synthetic dispatch window of a known N cycles, asserts `CMD_LATENCY_LAST == N`) |

See `verif/cocotb_tb/matrix_engine/README.md`, `verif/cocotb_tb/dma/README.md`,
`verif/cocotb_tb/top/README.md`, and `verif/cocotb_tb/pmu/README.md` for the
actual observed failure signatures (exact mismatch addresses/values) from
running the suites with these bugs present.
