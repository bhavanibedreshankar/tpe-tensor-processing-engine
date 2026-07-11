# Debug infrastructure testbench. See docs/flows/build_flow.md section 4
# for the per-block Makefile pattern this follows.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := tpe_debug
MODULE   := test_debug

REPO_ROOT := $(abspath ../../..)

VERILOG_SOURCES := \
	$(REPO_ROOT)/rtl/include/tpe_pkg.sv \
	$(REPO_ROOT)/rtl/include/tpe_regs_pkg.sv \
	$(REPO_ROOT)/rtl/common/sync_fifo.sv \
	$(REPO_ROOT)/rtl/debug/tpe_debug.sv \
	$(REPO_ROOT)/verif/sva/debug_sva.sv \
	$(REPO_ROOT)/verif/coverage/debug_cov.sv

SIM_BUILD := sim_build

export PYTHONPATH := $(REPO_ROOT):$(PYTHONPATH)

# See docs/flows/build_flow.md section 4: always the three explicit
# coverage flags, never the blanket --coverage (Verilator 5.050 compiler bug
# with concurrent SVA assertions).
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user
EXTRA_ARGS += -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL
EXTRA_ARGS += --trace --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves clean-all
waves:
	gtkwave $(SIM_BUILD)/dump.vcd &

clean-all: clean
	rm -rf sim_build results.xml coverage.dat dump.vcd debug_scoreboard_work __pycache__
