# model/ -- C++ golden reference model

**Status: `Scratchpad` done (M1).** Next: `MacArray`/`Accumulator` (M2),
`DmaEngine` (M3), `CommandProcessor` (M4).

A C++17, object-oriented reference model mirroring the RTL's block
structure. Built as a small CLI (`tpe_model`) that consumes a binary
stimulus file a pyuvm scoreboard wrote during a test and writes a binary
result file that same scoreboard reads back to diff against RTL-observed
state (see `verif/cocotb_tb/env/golden_model.py` and
`verif/cocotb_tb/sram/scoreboard.py` for the first working example: the
`sram-apply` subcommand). This is the "C++ based reference model" and the
scoreboarding oracle in one.

Deliberately file-based rather than a Python binding (pybind11): keeps the
model buildable/testable in complete isolation from the RTL/cocotb
toolchain (`model/tests/`, plain C++ unit tests, no simulator required),
and avoids pybind11 build fragility across environments.

```
include/Scratchpad.hpp   golden model of rtl/sram/tpe_sram.sv
src/main.cpp             tpe_model CLI (sram-apply subcommand so far)
tests/test_scratchpad.cpp  dependency-free unit tests (no Catch2/GoogleTest)
Makefile                  `make` builds tpe_model, `make test` runs unit tests
```

Build and test:
```
make        # builds build/tpe_model
make test   # builds and runs build/test_scratchpad
```
