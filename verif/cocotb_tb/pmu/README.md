# PMU testbench

Verifies `rtl/pmu/tpe_pmu.sv` standalone -- drives the real AXI4-Lite MMIO
port with `Axi4LiteDriver` and drives the six event inputs (`mac_active`/
`dma_wait`/`sched_stall`/`sched_idle`/`dispatch_start`/`cmd_done_valid`)
directly from Python. No pyuvm env/scoreboard: register pokes plus plain
`assert`s on read-back values are simpler and just as effective for a
six-register counter bank (same call made for the Command Processor's
own directed IRQ tests in `verif/cocotb_tb/top/test_top.py`).

`tpe_pmu` doesn't need a real Scheduler behind it to prove its own counter
logic -- see `verif/cocotb_tb/top/test_top.py`'s `pmu_debug_integration_test`
for the complementary check that the real top-level's AXI4-Lite router
actually reaches this block through real Scheduler-driven events.

## Tests

- `counter_basics_test` -- `CTRL.ENABLE` gates all counting (including
  `CYCLE_COUNT`); each event counter increments exactly once per asserted
  cycle of its input; `CTRL.RESET_COUNTERS` zeroes every *live* counter
  (see `tpe_pmu.sv`'s header comment on why `CMD_LATENCY_LAST` is
  deliberately excluded) and counting resumes once released.
- `latency_test` -- directed: drives a synthetic `dispatch_start`..
  `cmd_done_valid` window of a known `N` cycles and checks
  `CMD_LATENCY_LAST` reads back `N`.

Run:
```
make
make waves
```

## Status: 1 intentional bug present (see docs/verification/bug_list.md)

`counter_basics_test` passes; `latency_test` **fails by design**:

```
CMD_LATENCY_LAST=4, want 5
```

Bug #7: `tpe_pmu.sv`'s completion-cycle capture of `latency_ctr_q` races
its own increment -- both are nonblocking assignments evaluated off the
same (pre-update) register value in the same cycle, so the capture misses
the completion cycle's own tick and undercounts by exactly 1. See
`tpe_pmu.sv`'s inline comment at the bug site and
`docs/verification/bug_list.md` for the full writeup.

Note: `counter_basics_test`'s exact-value assertions read the counters
*after* writing `CTRL.ENABLE=0` to freeze them first -- these are live
free-running counters, so a read issued while still counting would see
extra ticks accrued during the read's own AXI4-Lite handshake cycles
(caught during bring-up: an early version of this test asserted exact
values against still-counting registers and intermittently over-counted).
