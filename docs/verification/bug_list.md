# TPE Intentional Bug Catalog

This repo's RTL contains deliberately injected bugs, added block-by-block as
each milestone lands, to prove the verification environment (assertions,
scoreboard, coverage) actually catches real defects. Each entry below is
filled in when its bug is injected -- **not before** -- so this file always
reflects the true current state of the RTL, not a forward-looking plan.

Columns: which test(s) are expected to fail, what the observable symptom is
(assertion fire / scoreboard mismatch / coverage gap), and root cause.

## Status

3 bugs injected, all in the Matrix Compute Engine (M2). All three were
chosen deliberately so `matmul_sanity_test` (full-width tile, k=ROWS,
n=COLS, zero C_in, no overflow) stays green -- they only surface on the
narrower/nonzero/overflow paths `matmul_random_test` and
`matmul_overflow_test` exercise, exactly as a real regression suite would
catch them (a passing smoke test does not mean a clean design).

| # | Block | File:Line | Symptom | Root cause | Caught by |
|---|---|---|---|---|---|
| 1 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:154,166` | Wrong GEMM values whenever `dim_k < ROWS`; row `k_q` (one past the intended last row) spuriously contributes to the sum. Never fires when `dim_k == ROWS` (the array's full physical width), so a naive full-width smoke test would never catch it. | Off-by-one in the row-contribution gate: `(r <= k_q)` should be `(r < k_q)` (row indices are 0-based, so row index `k_q` is one past the last valid row `k_q-1`). | `matmul_random_test` (several iterations use `dim_k < ROWS`) |
| 2 | matrix_engine | `rtl/matrix_engine/matrix_engine_ctrl.sv:193` | Wrong GEMM values in output columns >= 2 whenever C_in (the accumulator seed) is nonzero. Invisible when C_in is all-zero (sanity test), since adding a *misaligned* zero is still zero. | Off-by-one tap selection in the per-column seed skew chain: columns `c >= 2` read `seed_chain[c-2]` instead of `seed_chain[c-1]`, feeding the seed value that was actually meant for `m-1` (one row of C_in too early) into column c's accumulation for the current m. | `matmul_random_test` (nonzero C_in, `dim_n >= 3`) |
| 3 | matrix_engine | `rtl/matrix_engine/pe.sv:50` | Negative accumulator overflow silently wraps (two's-complement) instead of saturating to `INT32_MIN`, while positive overflow still saturates correctly. `overflow_sticky` still correctly reports that an overflow happened either way (detection and clamping are separate logic) -- only the clamped *value* is wrong, which is exactly why checking both the value and the status flag independently matters. | Asymmetric ternary: `acc_in[MSB] ? sum : AccumMax` should be `acc_in[MSB] ? AccumMin : AccumMax` -- the negative-overflow branch returns the unclamped wrapped `sum` instead of `AccumMin`. | `matmul_overflow_test` (`overflow_neg` case specifically; `overflow_pos` stays green) |

See `verif/cocotb_tb/matrix_engine/README.md` for the actual observed
failure signatures (exact mismatch addresses/values) from running the
suite with these bugs present.
