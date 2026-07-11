# Debug infrastructure testbench

Verifies `rtl/debug/tpe_debug.sv` standalone -- drives the real AXI4-Lite
MMIO port with `Axi4LiteDriver` and drives the scheduler-completion feed
(`sched_done_valid`/`sched_done_tag`/`sched_done_status`/
`sched_done_opcode`) directly from Python. Same "no pyuvm env needed for a
small register bank" rationale as `verif/cocotb_tb/pmu/`.

`tpe_debug` doesn't need a real Scheduler behind it to prove its own trace-
FIFO/error-latch logic -- see `verif/cocotb_tb/top/test_top.py`'s
`pmu_debug_integration_test` for the complementary check that the real
top-level's AXI4-Lite router actually reaches this block through real
Scheduler-driven completions.

## Tests

- `trace_pop_test` -- push two completions, check
  `TRACE_STATUS.TRACE_COUNT`, pop both via `TRACE_RDATA` and check the
  opcode/tag/status packing round-trips, check the FIFO reports empty
  again.
- `error_latch_test` -- `ERROR_CODE`/`ERROR_TAG` only latch on a non-
  `STAT_OK` completion, and track the *most recent* error (not the first).
- `trace_disabled_test` -- `CTRL.TRACE_ENABLE=0` (the reset default):
  completions don't get pushed into the trace FIFO, but the error latch
  still fires (it's independent of tracing).

Run:
```
make
make waves
```

## Status: no intentional bugs (all 3 tests pass)

## Bringing this up

`TRACE_RDATA` needed a 3-state read FSM (`R_IDLE -> R_POP_WAIT -> R_DATA`)
rather than the 2-state pattern every other AXI4-Lite-visible register in
this repo uses (`tpe_cmd_proc.sv`, `tpe_pmu.sv`) -- it's the only *popping*
read here, and `rtl/common/sync_fifo.sv`'s registered output needs one
extra cycle to become valid after the `rd_en` pulse. Worth knowing before
adding any future FIFO-backed read register: a plain address-latch-then-
return (fine for every plain register read) silently returns stale data
for a popping one. See `tpe_debug.sv`'s header comment.
