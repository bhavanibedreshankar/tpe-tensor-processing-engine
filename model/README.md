# model/ -- C++ golden reference model

**Status: `Scratchpad` (M1), `matmul`/`MacArray` (M2), `DmaEngine` (M3)
done.** Next: `CommandProcessor` (M4).

A C++17, object-oriented reference model mirroring the RTL's block
structure. Built as a small CLI (`tpe_model`) that consumes a binary
stimulus file a pyuvm scoreboard wrote during a test and writes a binary
result file that same scoreboard reads back to diff against RTL-observed
state (see `verif/cocotb_tb/env/golden_model.py`,
`verif/cocotb_tb/sram/scoreboard.py` for the first working example: the
`sram-apply` subcommand, and `verif/cocotb_tb/matrix_engine/scoreboard.py`
for `matmul` -- untimed GEMM math with the same per-addition saturation
semantics as `rtl/matrix_engine/pe.sv`). This is the "C++ based reference
model" and the scoreboarding oracle in one.

Deliberately file-based rather than a Python binding (pybind11): keeps the
model buildable/testable in complete isolation from the RTL/cocotb
toolchain (`model/tests/`, plain C++ unit tests, no simulator required),
and avoids pybind11 build fragility across environments.

```
include/Scratchpad.hpp   golden model of rtl/sram/tpe_sram.sv (+ load_image bulk loader)
include/MacArray.hpp     golden model of rtl/matrix_engine/*.sv (matmul + saturating_add)
include/DmaEngine.hpp    golden model of rtl/dma/tpe_dma.sv (row-copy between two Scratchpads)
src/main.cpp             tpe_model CLI (sram-apply, matmul, dma-apply subcommands)
tests/test_scratchpad.cpp  dependency-free unit tests (no Catch2/GoogleTest)
tests/test_matmul.cpp      ditto, incl. saturation-on-overflow cases
tests/test_dma.cpp         ditto, incl. multi-row copies in both directions
Makefile                  `make` builds tpe_model, `make test` runs unit tests
```

Build and test:
```
make        # builds build/tpe_model
make test   # builds and runs build/test_scratchpad
```
