# TPE Intentional Bug Catalog

This repo's RTL contains deliberately injected bugs, added block-by-block as
each milestone lands, to prove the verification environment (assertions,
scoreboard, coverage) actually catches real defects. Each entry below is
filled in when its bug is injected -- **not before** -- so this file always
reflects the true current state of the RTL, not a forward-looking plan.

Bugs #1-#7 are RTL defects. Bugs #8-#10 are a different, deliberately
distinct category: **golden-model/testbench integration bugs** (a call-site
config/framing mismatch between a scoreboard and `tpe_model`, not a DUT
defect). Together they exercise five distinct failure *types* (not just
distinct message text), so `run_sim`'s status/monitor/summary tables and
its `FAILURE SIGNATURE` column (`docs/flows/run_sim_flow.md` section 10)
show which category actually caught a given test, rather than everything
reading as a generic `AssertionError`:

- `AssertionError` -- a plain Python `assert` (bugs #1-#3, the
  `MatmulScoreboard`'s data-compare check) -- kept as-is, not converted,
  since a bare assert is exactly what most of this repo's checks
  legitimately are and should stay recognizable as such.
- `MismatchError` (`verif/cocotb_tb/env/errors.py`) -- a *different*
  scoreboard's data-compare mismatch (bug #4, `DmaScoreboard`), given its
  own distinct type specifically so it doesn't read identically to #1-#3's
  plain assert despite being conceptually similar.
- `UVMError` / `UVMFatalError` -- `pyuvm.uvm_error()`/`uvm_fatal()` (both
  already part of pyuvm, not custom): a single status/register check
  failed (bugs #5-#7).
- `CModelError` (`verif/cocotb_tb/env/golden_model.py`) -- `tpe_model`
  itself failing outright (nonzero exit), as opposed to its output
  mismatching RTL (bugs #8-#10).

**Which of these are actually an RTL-vs-golden-model comparison, and which
aren't** (five category *names* don't all mean the same kind of check):

- `AssertionError` (#1-#3) and `MismatchError` (#4) *are* genuine
  RTL-vs-cmodel diffs: `MatmulScoreboard.check()` compares the RTL's
  observed output tile against `run_tpe_model("matmul", ...)`'s computed
  result; `DmaScoreboard.check_row()` compares an RTL-observed row
  (backdoor-read from the DUT) against `expected_row()`, which is
  populated by `run_tpe_model("dma-apply", ...)`'s output. Both raise only
  when the RTL and the C++ model actually disagree.
- `UVMError`/`UVMFatalError` (#5-#7) are **not** a data comparison at all
  -- each checks one RTL register/status value against a constant known
  correct from the test's own setup (e.g. `status_last_status(status) ==
  STAT_OK`, `latency == n_cycles`). No golden model or shadow model is
  involved; it's "does this register read what the architecture spec says
  it should."
- `CModelError` (#8-#10) is **not** a comparison against RTL at all --
  these don't even drive the DUT (see each test's docstring). They check
  that `tpe_model`'s own CLI rejects a malformed/misconfigured invocation
  (wrong depth, mismatched stimulus size); it's a model/testbench
  call-contract check, independent of DUT behavior.
- Worth knowing if auditing further: SRAM's scoreboard
  (`verif/cocotb_tb/sram/scoreboard.py`) actually has *two* separate check
  mechanisms -- a live per-cycle check against a lightweight Python shadow
  dict (`self.shadow`, not the C++ model, see that file's own docstring
  for why), and a separate whole-image cross-check against the real
  `tpe_model sram-apply` golden model. None of the 10 catalogued bugs
  above currently exercise the Python-shadow path (`sram_sanity_test`/
  `sram_random_test` both stay green -- no injected bug targets
  `rtl/sram/tpe_sram.sv` itself), so every failure in the table below that
  looks like a "mismatch" is specifically an RTL-vs-cmodel diff, not a
  shadow-model diff, even though the RTL-vs-shadow mechanism exists
  elsewhere in the codebase.

Columns: which test(s) are expected to fail, what the observable symptom is
(assertion fire / scoreboard mismatch / coverage gap / cmodel rejection),
root cause, and which exception category it's caught as.

## Status

10 bugs injected: 3 in the Matrix Compute Engine (M2), 1 in the DMA Engine
(M3), 2 in the Command Processor/Scheduler (M4), 1 in the PMU (M5) -- all
RTL defects -- plus 3 golden-model/testbench integration bugs (M7, one per
block with a `tpe_model` call site: sram/dma/matrix_engine), added
specifically to diversify the failure-category mix beyond generic
`AssertionError`. Each RTL bug was chosen deliberately so the relevant
block's sanity/golden-path test stays green -- they only surface on
narrower/nonzero/multi-burst/boundary/overflow/timing-sensitive paths that
random and directed edge-case tests exercise, exactly as a real regression
suite would catch them (a passing smoke test does not mean a clean design).
The 3 integration bugs are unconditional (always fail, not seed-dependent)
and don't touch the DUT at all -- see each one's entry below.

**M7 final regression proof** (all four tiers, `make sanity|smoke|daily|
random`): `sanity` 6/6 pass (no bug-hunting tests in this tier by design);
`smoke` 13 pass / 8 FAIL out of 21 (61.9% pass, 38.1% fail -- bugs #3-#10,
every directed/integration bug-catching test in this tier, consistently);
`daily` 59 pass / 41 FAIL out of 100 (includes every directed/integration
bug-catching test, since `daily.yaml` always includes all of `smoke.yaml`,
plus a random sweep of bugs #1/#2/#4); `random` 60 pass / 40 FAIL out of 100
(a pure `kind: random` sweep -- no directed/integration entries at all, so
#8-#10 don't touch this tier's ratio -- bugs #1/#2 firing on most
`matmul_random_test` seeds, #4 firing on `dma_random_test` seeds landing on
its trigger residue). See the note below on why `daily` sits a couple
points under smoke's 60% floor. Zero `ERROR`/`TIMEOUT`
(infrastructure-health) results across every tier in this pass. See
`docs/flows/regression_flow.md` section 7 for the exact expected-FAIL
breakdown this is checked against.

**Why `daily`'s pass rate sits a little under smoke's/random's**: bugs
#1/#2 have always fired on a large majority of random-sweep seeds
(documented here well before #8-#10 existed), which is why `random`'s pass
rate has historically sat right at ~60/40 already. `daily.yaml` additionally
includes every directed/integration test verbatim (via
`tools/gen_tests.py`'s `directed` list), so adding 3 more always-failing
integration tests (#8-#10) grew its *guaranteed*-fail floor by 3, nudging
what was already right at the ~60/40 boundary slightly under it. Fixing
that would mean changing bug #1/#2's underlying trigger rate or how many
seeds `tools/gen_tests.py` sweeps -- out of scope for what #8-#10 were
actually for (category diversity), so it's called out here rather than
silently tuned away.

| # | Block | File:Line | Symptom | Root cause | Caught by | Category |
|---|---|---|---|---|---|---|
| 1 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:154,166` | Wrong GEMM values whenever `dim_k < ROWS`; row `k_q` (one past the intended last row) spuriously contributes to the sum. Never fires when `dim_k == ROWS` (the array's full physical width), so a naive full-width smoke test would never catch it. | Off-by-one in the row-contribution gate: `(r <= k_q)` should be `(r < k_q)` (row indices are 0-based, so row index `k_q` is one past the last valid row `k_q-1`). | `matmul_random_test` (several iterations use `dim_k < ROWS`) | `AssertionError` |
| 2 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:193` | Wrong GEMM values in output columns >= 2 whenever C_in (the accumulator seed) is nonzero. Invisible when C_in is all-zero (sanity test), since adding a *misaligned* zero is still zero. | Off-by-one tap selection in the per-column seed skew chain: columns `c >= 2` read `seed_chain[c-2]` instead of `seed_chain[c-1]`, feeding the seed value that was actually meant for `m-1` (one row of C_in too early) into column c's accumulation for the current m. | `matmul_random_test` (nonzero C_in, `dim_n >= 3`) | `AssertionError` |
| 3 | matrix_engine | `rtl/matrix_engine/pe.sv:50` | Negative accumulator overflow silently wraps (two's-complement) instead of saturating to `INT32_MIN`, while positive overflow still saturates correctly. `overflow_sticky` still correctly reports that an overflow happened either way (detection and clamping are separate logic) -- only the clamped *value* is wrong, which is exactly why checking both the value and the status flag independently matters. | Asymmetric ternary: `acc_in[MSB] ? sum : AccumMax` should be `acc_in[MSB] ? AccumMin : AccumMax` -- the negative-overflow branch returns the unclamped wrapped `sum` instead of `AccumMin`. | `matmul_overflow_test` (`overflow_neg` case specifically; `overflow_pos` stays green) | `AssertionError` |
| 4 | dma | `rtl/dma/tpe_dma.sv:161` | SRAM->DDR transfers whose length leaves exactly 1 beat for a trailing burst (e.g. 17 rows = one 16-beat burst + one 1-beat burst) silently drop that final row -- it's never written to DDR. Only affects the write (SRAM->DDR) direction; only affects transfers where `n_rows % MAX_BURST_BEATS == 1`. The directed `dma_multiburst_write_test` (17 rows, SRAM->DDR) catches it reliably by construction. `dma_random_test`'s originally-hardcoded seed (11) happened not to roll that exact case, which is itself worth noting -- a green random regression is not proof of a clean design -- but M6's 100-seed daily/random sweeps (`tools/gen_tests.py`) show `dma_random_test` *does* hit it under other seeds (`n_rows = rng.randint(1, 40)` lands on the SRAM->DDR direction with `n_rows % 16 == 1` about 1 time in 16, e.g. seed 10030): a random test's seed choice matters as much as the test itself. | Off-by-one in the burst-continuation check: `beats_remaining_q <= BeatsWidth'(1)` should be `beats_remaining_q == BeatsWidth'(0)` -- at this point in the FSM all of the just-completed burst's beats are already accounted for, so "1 remaining" means one more (small) burst is still needed, not that the transfer is done. | `dma_multiburst_write_test` (always); `dma_random_test` (only on seeds landing on the trigger residue -- not reliable alone) | `MismatchError` |
| 5 | scheduler | `rtl/scheduler/tpe_scheduler.sv:84` | `CMD_MATMUL` with `dim_n == COLS` (the array's full physical width -- a legitimate, exactly-fitting tile, not an out-of-range one) is wrongly rejected with `STAT_BAD_DIM` instead of dispatched. `matmul_flow_test` uses `dim_n=5 < COLS`, so it never hits this boundary. | Off-by-one in the bounds check: `cmd_q.dim_n < TILE_DIM_WIDTH'(COLS)` should be `<=` -- `dim_n == COLS` means "use all COLS columns," which is in range, not one past it. | `matmul_full_width_test` (directed `dim_n == COLS`) | `UVMError` |
| 6 | cmd_proc | `rtl/command_processor/tpe_cmd_proc.sv:242` | Writing 1 to `IRQ_STATUS.CMD_ERROR` (bit 1) alone does nothing -- the bit never clears unless `CMD_DONE` (bit 0) is *also* being written 1 in the same access, and doing so clears both regardless of which the host intended. | Copy-paste-shaped bit-width bug: the write-1-to-clear mask is built from `s_wdata[0]` broadcast to both bits (`~{2{s_wdata[0]}}`) instead of using each bit's own `s_wdata` value (`~s_wdata[1:0]`). | `irq_independent_clear_test` (forces both bits set, clears `CMD_ERROR` alone, checks `CMD_DONE` survives) | `UVMFatalError` (core IRQ-status plumbing every completion path depends on, not a single-scenario check) |
| 7 | pmu | `rtl/pmu/tpe_pmu.sv` (the `if (cmd_done_valid)` branch capturing `cmd_latency_last_q`) | `PMU_CMD_LATENCY_LAST` reads exactly 1 cycle lower than the command's true dispatch-to-completion cycle count, every time, for every command. Invisible to any test that doesn't independently hand-derive the expected cycle count (which is why this is a PMU-only bug: `pmu_debug_integration_test` in the top-level suite only checks `CYCLE_COUNT > 0`, not an exact latency value). | Same-cycle nonblocking-assignment ordering: on the `cmd_done_valid` cycle, `latency_ctr_q`'s own completion-cycle increment (`latency_ctr_q <= latency_ctr_q + 1`) and `cmd_latency_last_q`'s capture (`cmd_latency_last_q <= latency_ctr_q`) both read the *old* (pre-increment) value of `latency_ctr_q` in the same cycle -- the capture should read `latency_ctr_q + 32'd1` to include the completion cycle itself. | `latency_test` (drives a synthetic dispatch window of a known N cycles, asserts `CMD_LATENCY_LAST == N`) | `UVMError` |
| 8 | sram (verification-side, not RTL) | `verif/cocotb_tb/sram/test_sram.py` (`SramCModelIntegrationTest`) | Scoreboard/golden-model config drift, not a DUT defect: the golden model is built believing `depth=SRAM_DEPTH-1`. `SramDirectedSeq`'s write to the real last row (`SRAM_DEPTH-1`) is perfectly legal on real hardware, but `model/include/Scratchpad.hpp`'s `check_addr` rejects that same address as out-of-range for the model's (wrong) belief of depth. | Deliberately wrong `depth` argument passed to `SramEnv`/`SramScoreboard` in the test, one less than the DUT's actual `SRAM_DEPTH`. | `sram_cmodel_integration_test` (always) | `CModelError` |
| 9 | dma (verification-side, not RTL) | `verif/cocotb_tb/dma/test_dma.py` (`dma_cmodel_integration_test`) | A hand-built `dma-apply` stimulus claims one SRAM row more than the DDR/SRAM image bytes actually supplied; `model/src/main.cpp`'s `cmd_dma_apply` stimulus-file size check legitimately rejects it. Doesn't drive the DUT at all -- purely a model/testbench call-contract check. | Deliberately wrong `sram_depth` argument (`+1`) passed to `run_tpe_model("dma-apply", ...)`. | `dma_cmodel_integration_test` (always) | `CModelError` |
| 10 | matrix_engine (verification-side, not RTL) | `verif/cocotb_tb/matrix_engine/test_matrix_engine.py` (`matmul_cmodel_integration_test`) | A hand-built `matmul` stimulus header claims `N=3` but only 2 columns of B/C_in data are actually supplied; `model/src/main.cpp`'s `cmd_matmul` stimulus-file size check legitimately rejects it. Doesn't drive the DUT at all. | Deliberately mismatched header `N` vs. actual column count in the hand-built stimulus file. | `matmul_cmodel_integration_test` (always) | `CModelError` |

See `verif/cocotb_tb/matrix_engine/README.md`, `verif/cocotb_tb/dma/README.md`,
`verif/cocotb_tb/top/README.md`, and `verif/cocotb_tb/pmu/README.md` for the
actual observed failure signatures (exact mismatch addresses/values) from
running the suites with these bugs present.
