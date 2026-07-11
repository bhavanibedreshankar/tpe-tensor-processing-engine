# Top-level end-to-end testbench. See docs/flows/build_flow.md section 4
# for the per-block Makefile pattern this follows.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := top_test_harness
MODULE   := test_top

REPO_ROOT := $(abspath ../../..)

VERILOG_SOURCES := \
	$(REPO_ROOT)/rtl/include/tpe_pkg.sv \
	$(REPO_ROOT)/rtl/include/tpe_regs_pkg.sv \
	$(REPO_ROOT)/rtl/common/sync_fifo.sv \
	$(REPO_ROOT)/rtl/common/dp_ram.sv \
	$(REPO_ROOT)/rtl/matrix_engine/pe.sv \
	$(REPO_ROOT)/rtl/matrix_engine/mac_array.sv \
	$(REPO_ROOT)/rtl/matrix_engine/matrix_engine_ctrl.sv \
	$(REPO_ROOT)/rtl/matrix_engine/matrix_engine.sv \
	$(REPO_ROOT)/rtl/dma/tpe_dma.sv \
	$(REPO_ROOT)/rtl/command_processor/tpe_cmd_proc.sv \
	$(REPO_ROOT)/rtl/scheduler/tpe_scheduler.sv \
	$(REPO_ROOT)/rtl/pmu/tpe_pmu.sv \
	$(REPO_ROOT)/rtl/debug/tpe_debug.sv \
	$(REPO_ROOT)/rtl/top/tpe_top.sv \
	$(REPO_ROOT)/verif/models/axi4_ddr_model.sv \
	$(REPO_ROOT)/verif/cocotb_tb/top/top_test_harness.sv \
	$(REPO_ROOT)/verif/sva/cmd_proc_sva.sv \
	$(REPO_ROOT)/verif/sva/pmu_sva.sv \
	$(REPO_ROOT)/verif/sva/debug_sva.sv \
	$(REPO_ROOT)/verif/coverage/cmd_proc_cov.sv \
	$(REPO_ROOT)/verif/coverage/pmu_cov.sv \
	$(REPO_ROOT)/verif/coverage/debug_cov.sv

SIM_BUILD := sim_build

export PYTHONPATH := $(REPO_ROOT):$(PYTHONPATH)

EXTRA_ARGS += -GDDR_DEPTH=1024
EXTRA_ARGS += --assert --coverage-line --coverage-toggle --coverage-user
EXTRA_ARGS += -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNSIGNED
EXTRA_ARGS += --trace --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: model waves clean-all
model:
	$(MAKE) -C $(REPO_ROOT)/model

$(SIM_BUILD)/Vtop.mk: model

waves:
	gtkwave $(SIM_BUILD)/dump.vcd &

clean-all: clean
	rm -rf sim_build results.xml coverage.dat dump.vcd top_scoreboard_work __pycache__
