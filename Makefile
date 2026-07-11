# Tensor Processing Engine (TPE) -- top-level build/verification entry point.
#
# This Makefile grows alongside the milestones in the plan (see README.md):
# targets like `sanity`/`smoke`/`daily`/`random` are added once
# tools/regression.py and the per-block testbenches exist (M1-M6). For now
# it covers the foundation: environment setup, register-map generation,
# RTL lint, and the toolchain smoke test.

SHELL := /bin/bash
REPO_ROOT := $(abspath .)
VENV := $(REPO_ROOT)/.venv
PYTHON := $(VENV)/bin/python3
PIP := $(VENV)/bin/pip

RTL_PKG := rtl/include/tpe_pkg.sv rtl/include/tpe_regs_pkg.sv
RTL_COMMON := rtl/common/sync_fifo.sv rtl/common/round_robin_arb.sv rtl/common/dp_ram.sv

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "TPE build/verification targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: venv
venv: ## Create/refresh the project virtualenv from tools/requirements.txt
	@test -d $(VENV) || python3 -m venv $(VENV)
	$(PIP) install --upgrade pip -q
	$(PIP) install -q -r tools/requirements.txt
	@echo "venv ready: $(VENV)"

.PHONY: regmap
regmap: venv ## Regenerate SV/C++/Markdown from docs/register_map/tpe_regs.yaml
	$(PYTHON) tools/regmap_gen.py

.PHONY: lint
lint: ## Lint all current RTL with verilator --lint-only
	@echo "== linting foundation RTL =="
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
		$(RTL_PKG) $(RTL_COMMON) \
		--top-module sync_fifo 2>&1 | tail -n +1
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
		$(RTL_PKG) rtl/common/round_robin_arb.sv --top-module round_robin_arb
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
		$(RTL_PKG) rtl/common/dp_ram.sv --top-module dp_ram
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
		$(RTL_PKG) rtl/common/dp_ram.sv rtl/sram/tpe_sram.sv --top-module tpe_sram
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNSIGNED \
		$(RTL_PKG) rtl/common/dp_ram.sv rtl/matrix_engine/pe.sv rtl/matrix_engine/mac_array.sv \
		rtl/matrix_engine/matrix_engine_ctrl.sv rtl/matrix_engine/matrix_engine.sv --top-module matrix_engine
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		$(RTL_PKG) rtl/dma/tpe_dma.sv --top-module tpe_dma
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		rtl/common/dp_ram.sv verif/models/axi4_ddr_model.sv --top-module axi4_ddr_model
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		$(RTL_PKG) rtl/common/sync_fifo.sv rtl/command_processor/tpe_cmd_proc.sv --top-module tpe_cmd_proc
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		$(RTL_PKG) rtl/scheduler/tpe_scheduler.sv --top-module tpe_scheduler
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		$(RTL_PKG) rtl/pmu/tpe_pmu.sv --top-module tpe_pmu
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		$(RTL_PKG) rtl/common/sync_fifo.sv rtl/debug/tpe_debug.sv --top-module tpe_debug
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNSIGNED -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		$(RTL_PKG) rtl/common/sync_fifo.sv rtl/common/dp_ram.sv \
		rtl/matrix_engine/pe.sv rtl/matrix_engine/mac_array.sv rtl/matrix_engine/matrix_engine_ctrl.sv rtl/matrix_engine/matrix_engine.sv \
		rtl/dma/tpe_dma.sv rtl/command_processor/tpe_cmd_proc.sv rtl/scheduler/tpe_scheduler.sv \
		rtl/pmu/tpe_pmu.sv rtl/debug/tpe_debug.sv rtl/top/tpe_top.sv \
		--top-module tpe_top
	@echo "lint OK"

.PHONY: toolchain-smoke
toolchain-smoke: venv ## Run the cocotb+pyuvm+Verilator toolchain smoke test
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/smoke clean-all && \
		$(MAKE) -C verif/cocotb_tb/smoke
	@echo "toolchain smoke test PASSED"

.PHONY: model
model: ## Build the C++ golden-model CLI + run its unit tests
	$(MAKE) -C model test
	$(MAKE) -C model

.PHONY: sim-sram
sim-sram: venv model ## Run the Local SRAM testbench (M1)
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/sram clean-all && \
		$(MAKE) -C verif/cocotb_tb/sram
	@echo "sram testbench PASSED"

.PHONY: sim-matrix-engine
sim-matrix-engine: venv model ## Run the Matrix Compute Engine testbench (M2) -- 2/3 tests FAIL by design, see docs/verification/bug_list.md
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/matrix_engine clean-all && \
		$(MAKE) -C verif/cocotb_tb/matrix_engine

.PHONY: sim-dma
sim-dma: venv model ## Run the DMA Engine testbench (M3) -- 1/4 tests FAIL by design, see docs/verification/bug_list.md
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/dma clean-all && \
		$(MAKE) -C verif/cocotb_tb/dma

.PHONY: sim-pmu
sim-pmu: venv ## Run the PMU testbench (M5) -- 1/2 tests FAIL by design, see docs/verification/bug_list.md
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/pmu clean-all && \
		$(MAKE) -C verif/cocotb_tb/pmu

.PHONY: sim-debug
sim-debug: venv ## Run the Debug infrastructure testbench (M5)
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/debug clean-all && \
		$(MAKE) -C verif/cocotb_tb/debug
	@echo "debug testbench PASSED"

.PHONY: sim-top
sim-top: venv model ## Run the top-level end-to-end testbench (M4/M5) -- 2/6 tests FAIL by design, see docs/verification/bug_list.md
	source $(VENV)/bin/activate && \
		$(MAKE) -C verif/cocotb_tb/top clean-all && \
		$(MAKE) -C verif/cocotb_tb/top

.PHONY: clean
clean: ## Remove simulation/build artifacts (keeps generated docs/register files)
	find . -name sim_build -type d -not -path './.venv/*' -exec rm -rf {} + 2>/dev/null || true
	find . -name '__pycache__' -type d -not -path './.venv/*' -exec rm -rf {} + 2>/dev/null || true
	find . \( -name 'coverage.dat' -o -name 'dump.vcd' -o -name 'results.xml' \) -not -path './.venv/*' -delete 2>/dev/null || true
	find . \( -name '*_coverage.xml' -o -name '*_scoreboard_work' -o -name 'matmul_scoreboard_work' -o -name 'dma_scoreboard_work' -o -name 'top_scoreboard_work' \) -not -path './.venv/*' -exec rm -rf {} + 2>/dev/null || true
	rm -rf verif/cocotb_tb/smoke/sim_build
	$(MAKE) -C model clean
	@echo "clean OK"

.PHONY: distclean
distclean: clean ## clean + remove the venv
	rm -rf $(VENV)
