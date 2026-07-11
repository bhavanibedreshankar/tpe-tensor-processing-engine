# Toolchain smoke test

Not part of the TPE verification suite. This is a throwaway DUT
(`rtl/smoke_counter.sv`, a plain up-counter) with a pyuvm testbench
(`test_smoke_counter.py`) whose only job is to prove that cocotb + pyuvm +
Verilator + SVA assertions + SV covergroups + structural coverage +
waveform dumping all work together on a given machine, using the exact
class-based (driver/monitor/scoreboard/sequencer/sequence/env/test) pattern
every real block's testbench will follow.

Run it:

```
make            # from this directory, or `make toolchain-smoke` from the repo root
make waves      # opens the VCD in GTKWave
make clean-all  # remove build artifacts
```

If this fails, nothing else in `verif/` will work either -- fix this first.

See the note at the top of `Makefile` about why the coverage flags are
`--coverage-line --coverage-toggle --coverage-user` and not the blanket
`--coverage` (Verilator 5.050 compiler bug when combined with concurrent
SVA assertions).
