# Matrix Compute Engine testbench

Verifies `rtl/matrix_engine/{pe,mac_array,matrix_engine_ctrl,matrix_engine}.sv`
-- the weight-stationary systolic array implementing `C = A x B + C` (int8
operands, int32 saturating accumulator). See
`rtl/matrix_engine/matrix_engine_ctrl.sv`'s header comment for the full
systolic timing derivation (why row r / column c each need their own
pipeline delay).

DUT is instantiated at ROWS=COLS=4, MAX_M=32 (see `Makefile`) for fast
simulation -- the architecture's default is 16x16, scaling to 32x32/64x64
with the same interface (docs/architecture/tpe_architecture_spec.md
section 3.5), so a 4x4 array exercises the same control/timing logic.

## Tests

- `matmul_sanity_test` -- one directed 3x4x4 GEMM (full array width, zero
  C_in), hand-checkable.
- `matmul_random_test` -- 10 constrained-random GEMMs with varied
  M/K/N (including K<ROWS and N<COLS, i.e. tiles narrower than the array)
  and nonzero C_in, seeded for reproducibility.
- `matmul_overflow_test` -- directed positive- and negative-saturation
  cases, checking both the clamped value and the `overflow_sticky` status
  bit independently.

All three load A/B/C_in through the four dp_ram-style buffer ports (reusing
`verif/cocotb_tb/env/SyncPortAgent` from M1 -- see `sequences.py`), drive
`start`/`dim_m`/`dim_k`/`dim_n` directly (this control interface is
superseded by the real Command Processor register interface in M4), wait
for `done`, read the result tile back, and diff it against the C++ golden
model (`model/build/tpe_model matmul`, see `scoreboard.py`).

Run:
```
make -C model               # build tpe_model first (or `make model` here)
make                         # runs all three tests
make TESTCASE=matmul_sanity_test   # run just one
make waves
```

## Status: 3 intentional bugs present (see docs/verification/bug_list.md)

`matmul_sanity_test` passes; `matmul_random_test` and `matmul_overflow_test`
**fail by design** against the current RTL. Observed failure signatures:

- `matmul_random_test`, iteration with `dim_k=2 < ROWS=4` and `dim_n=4`:
  mismatches cluster in output columns 2-3 only (columns 0-1 correct) --
  the seed-skew off-by-one (bug #2) plus the narrow-K row-inclusion
  off-by-one (bug #1).
- `matmul_overflow_test`: `overflow_pos` passes; `overflow_neg` fails with
  `rtl=0x7fff05e8` (wrapped) vs `golden=0x80000000` (correctly saturated
  `INT32_MIN`) -- the asymmetric saturation bug (bug #3). `overflow_sticky`
  is `True` on both sides in both cases -- overflow *detection* is correct,
  only the *clamped value* is wrong for the negative case.

## A monitor timing bug worth knowing about (inherited from M1)

Two fixes live in the shared `verif/cocotb_tb/env/` components and apply
here too -- see `verif/cocotb_tb/sram/README.md` for the full writeup:
cocotb's `Clock` producing a valid `RisingEdge` at t=0, and
`SyncPortMonitor` sampling ctrl fields at `FallingEdge` (not the same edge
as `rdata`) so a scoreboard with persistent state never gets fed a
misaligned ctrl/data pair.

## Two real (non-intentional) bugs found and fixed while bringing this up

Worth knowing before writing the next block's testbench:

1. **Forgot to drive `rst_n`.** Unlike `tpe_sram` (no reset pin at all),
   `matrix_engine` has real sequential control state and needs an explicit
   reset pulse before `start` means anything. `_start_clock()` in
   `test_matrix_engine.py` handles this now.
2. **Output de-skewing across multiple in-flight rows.** An early version
   tried to assemble whole output rows from one shared staging register
   keyed off the *last* column's valid pulse. That's wrong whenever more
   than one `m` is in flight across the array at once (always true for
   COLS>1): an early column's *later* m overwrites its staged *earlier* m
   value before the late column's write for that earlier m fires, silently
   corrupting every column except the last. Fixed by giving each column its
   own independent output sub-buffer (see `matrix_engine_ctrl.sv` and
   `matrix_engine.sv`) instead of trying to re-synchronize a shared one.
3. **dp_ram strobe width mismatches.** dp_ram's strobe is one bit *per
   byte*, not per logical field -- `seed_buf`/`out_buf` pack multiple
   32-bit fields per row, so their strobe buses need `n_fields * 4` bits,
   not `n_fields` bits. Getting this wrong silently drops writes to the
   upper bytes of a word. Fixed in `matrix_engine.sv`'s buffer
   instantiations and `sequences.py`'s `_WriteRowsSeq`.
