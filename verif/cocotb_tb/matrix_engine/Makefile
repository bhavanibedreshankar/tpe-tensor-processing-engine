# Matrix Compute Engine testbench. See docs/flows/build_flow.md section 4
# for the per-block Makefile pattern this follows.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := matrix_engine
MODULE   := test_matrix_engine

REPO_ROOT := $(abspath ../../..)

VERILOG_SOURCES := \
	$(REPO_ROOT)/rtl/include/tpe_verbosity.svh \
	$(REPO_ROOT)/rtl/include/tpe_pkg.sv \
	$(REPO_ROOT)/rtl/common/dp_ram.sv \
	$(REPO_ROOT)/rtl/matrix_engine/pe.sv \
	$(REPO_ROOT)/rtl/matrix_engine/mac_array.sv \
	$(REPO_ROOT)/rtl/matrix_engine/matrix_engine_ctrl.sv \
	$(REPO_ROOT)/rtl/matrix_engine/matrix_engine.sv \
	$(REPO_ROOT)/verif/sva/matrix_engine_sva.sv \
	$(REPO_ROOT)/verif/coverage/matrix_engine_cov.sv

SIM_BUILD := sim_build

export PYTHONPATH := $(REPO_ROOT):$(PYTHONPATH)

# Small array for fast sim/tractable debug -- see test_matrix_engine.py's
# header comment; the architecture explicitly scales the same interface up
# to 16x16 and beyond.
EXTRA_ARGS += -GROWS=4 -GCOLS=4 -GMAX_M=32
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user
EXTRA_ARGS += -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNSIGNED
EXTRA_ARGS += --trace --trace-structs --autoflush

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: model waves clean-all
model:
	$(MAKE) -C $(REPO_ROOT)/model

$(SIM_BUILD)/Vtop.mk: model

waves:
	gtkwave $(SIM_BUILD)/dump.vcd &

clean-all: clean
	rm -rf sim_build results.xml coverage.dat dump.vcd matmul_scoreboard_work __pycache__
