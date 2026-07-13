# DMA Engine testbench. See docs/flows/build_flow.md section 4 for the
# per-block Makefile pattern this follows.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := dma_test_harness
MODULE   := test_dma

REPO_ROOT := $(abspath ../../..)

VERILOG_SOURCES := \
	$(REPO_ROOT)/rtl/include/tpe_verbosity.svh \
	$(REPO_ROOT)/rtl/include/tpe_pkg.sv \
	$(REPO_ROOT)/rtl/common/dp_ram.sv \
	$(REPO_ROOT)/rtl/sram/tpe_sram.sv \
	$(REPO_ROOT)/rtl/dma/tpe_dma.sv \
	$(REPO_ROOT)/verif/models/axi4_ddr_model.sv \
	$(REPO_ROOT)/verif/cocotb_tb/dma/dma_test_harness.sv \
	$(REPO_ROOT)/verif/sva/dma_sva.sv \
	$(REPO_ROOT)/verif/coverage/dma_cov.sv

SIM_BUILD := sim_build

export PYTHONPATH := $(REPO_ROOT):$(PYTHONPATH)

EXTRA_ARGS += -GDDR_DEPTH=256
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user
EXTRA_ARGS += -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY
EXTRA_ARGS += --trace --trace-structs --autoflush

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: model waves clean-all
model:
	$(MAKE) -C $(REPO_ROOT)/model

$(SIM_BUILD)/Vtop.mk: model

waves:
	gtkwave $(SIM_BUILD)/dump.vcd &

clean-all: clean
	rm -rf sim_build results.xml coverage.dat dump.vcd dma_scoreboard_work __pycache__
