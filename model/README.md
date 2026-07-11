# model/ -- C++ golden reference model

**Status: not yet implemented -- first classes land in M1** (`Scratchpad`),
extended in M2 (`MacArray`, `Accumulator`), M3 (`DmaEngine`), M4
(`CommandProcessor`).

A C++17, object-oriented reference model mirroring the RTL's block
structure. Built as a small CLI (`tpe_model`, once M1 lands) that consumes
the same command/descriptor stream the RTL executes and dumps final
SRAM/register state; the pyuvm scoreboards (`verif/cocotb_tb/*/`) invoke it
once per test and diff its output against what the RTL monitor observed.
This is the "C++ based reference model" and the scoreboarding oracle in one.

Deliberately file-based rather than a Python binding (pybind11): keeps the
model buildable/testable in complete isolation from the RTL/cocotb
toolchain (`model/tests/`, plain C++ unit tests, no simulator required),
and avoids pybind11 build fragility across environments.

Planned layout:
```
include/   Tensor, Scratchpad, MacArray, Accumulator, DmaEngine, CommandProcessor
src/       implementations
tests/     standalone C++ unit tests for the model itself
Makefile   builds tpe_model + runs model/tests/
```
