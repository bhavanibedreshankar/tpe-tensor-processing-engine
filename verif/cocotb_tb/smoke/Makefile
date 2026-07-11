# Toolchain smoke-test Makefile (cocotb + pyuvm + Verilator).
# Proves the full verification chain works before real RTL is written.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := smoke_counter
MODULE   := test_smoke_counter

VERILOG_SOURCES := $(abspath rtl/smoke_counter.sv)

SIM_BUILD := sim_build

# NOTE: use the explicit per-kind coverage flags, NOT the blanket "--coverage".
# Verilator 5.050 has a compiler bug (V3Localize internal error, "AstVarRef
# not under function") when --coverage is combined with a concurrent SVA
# assertion using |=> / disable-iff. The three explicit flags below produce
# the same line+toggle+functional coverage without hitting that bug.
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user -Wall -Wno-fatal -Wno-DECLFILENAME
EXTRA_ARGS += --trace --trace-structs

export VERILATOR_TRACE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves clean-all
waves:
	gtkwave $(SIM_BUILD)/dump.vcd &

clean-all: clean
	rm -rf sim_build results.xml coverage.dat __pycache__
