# DMA Engine testbench

Verifies `rtl/dma/tpe_dma.sv` (descriptor-based AXI4 master, DDR<->SRAM)
against `verif/models/axi4_ddr_model.sv` (behavioral AXI4 DDR slave) and a
real `rtl/sram/tpe_sram.sv`, wired together by `dma_test_harness.sv` (not
RTL in its own right -- see its header comment). tpe_dma drives
`tpe_sram`'s port A (as intended: "Port A is intended for DMA fill/drain"
per `tpe_sram.sv`) and `axi4_ddr_model`'s AXI slave ports; the testbench
gets backdoor read/write access to both memories through their other port,
reusing `verif/cocotb_tb/env/SyncPortAgent` from M1 for both.

## Tests

- `dma_sanity_test` -- one DDR->SRAM and one SRAM->DDR transfer, small
  (4 rows, single burst).
- `dma_random_test` -- 10 constrained-random transfers, varied direction,
  address, and length (1-40 rows, i.e. sometimes spanning multiple
  `MAX_BURST_BEATS`=16 bursts).
- `dma_multiburst_write_test` -- directed: 17 rows SRAM->DDR (16 +
  1 trailing beat), deterministically exercising the write-side
  burst-to-burst continuation regardless of what `dma_random_test`'s seed
  happens to roll. See "intentional bug" below -- this is exactly the test
  that reliably catches it, when `dma_random_test` sometimes doesn't.
- `dma_error_test` -- directed: a misaligned (non-16-byte-multiple)
  `desc_len` must raise `error`, not `done`.

Run:
```
make -C model               # build tpe_model first (or `make model` here)
make                         # runs all four tests
make waves
```

## Status: 1 intentional bug present (see docs/verification/bug_list.md)

`dma_sanity_test`, `dma_random_test`, and `dma_error_test` pass;
`dma_multiburst_write_test` **fails by design**. Observed failure:

```
[multiburst17] ddr row 16 mismatch: rtl=0x51054839... expected=0x32b55d35...
```

Row 16 (the 17th, trailing row -- the second burst's only beat) never gets
written to DDR; every other row is correct. Worth noting: the seeded
`dma_random_test` run that ships in this repo happens **not** to trigger
this bug (no iteration lands exactly on a `n_rows % MAX_BURST_BEATS == 1`
write-direction transfer) -- it's `dma_multiburst_write_test`, the directed
test built specifically to force that boundary, that catches it
deterministically. That's the point: a passing random regression is not
proof of a clean design, especially for boundary conditions a random
seed might just happen to miss.

## Bringing this up

Two bugs in *my own testbench/RTL derivation* were caught before any real
simulation even ran, by carefully tracing the timing by hand first (see the
comment in `rtl/dma/tpe_dma.sv` around `m_wdata`): an early version staged
`sram_rdata` into an extra register on the wrong cycle, capturing the
*previous* beat's data one cycle early -- exactly the M1/M2 "ctrl-and-data
sampled on the same edge as an update" class of bug, just spotted by
tracing through nonblocking-assignment semantics on paper instead of via a
failing simulation. Once removed in favor of using `dp_ram`'s own
registered output directly (which already holds the right value for
exactly as long as needed), `dma_sanity_test` passed on the first
simulation run.
