# Tensor Processing Engine (TPE) -- top-level build/verification entry point.
#
# Foundation (venv/regmap/lint/model), per-block `sim-<block>` targets, and
# the M6 regression tiers (`sanity`/`smoke`/`daily`/`random`, driven by
# tools/regression.py -- the local job-scheduler/farm replacement) plus
# `gen-tests`/`cov-merge`/`profile`. See docs/flows/regression_flow.md.

SHELL := /bin/bash
REPO_ROOT := $(abspath .)
VENV := $(REPO_ROOT)/.venv
PYTHON := $(VENV)/bin/python3
PIP := $(VENV)/bin/pip
JOBS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

RTL_PKG := rtl/include/tpe_pkg.sv rtl/include/tpe_regs_pkg.sv
RTL_COMMON := rtl/common/sync_fifo.sv rtl/common/round_robin_arb.sv rtl/common/dp_ram.sv
REGRESSION_BLOCKS := sram matrix_engine dma top pmu debug smoke

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
lint: venv ## Lint all current RTL with verilator --lint-only (tools/lint.py is the source of truth)
	$(PYTHON) tools/lint.py

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

.PHONY: build-all
build-all: venv model ## Build every block's simulation binary once (prereq for the regression tiers below)
	source $(VENV)/bin/activate && \
		for d in $(REGRESSION_BLOCKS); do $(MAKE) -C verif/cocotb_tb/$$d || exit 1; done

.PHONY: gen-tests
gen-tests: venv ## Regenerate verif/testlists/daily.yaml + random.yaml from standalone.yaml + smoke.yaml
	$(PYTHON) tools/gen_tests.py

.PHONY: sanity
sanity: build-all ## Run the sanity regression tier (~1 test/block, tools/regression.py)
	source $(VENV)/bin/activate && $(PYTHON) tools/regression.py sanity --jobs $(JOBS)

.PHONY: smoke
smoke: build-all ## Run the smoke regression tier (~17 tests) -- some FAIL by design, see docs/verification/bug_list.md
	source $(VENV)/bin/activate && $(PYTHON) tools/regression.py smoke --jobs $(JOBS)

.PHONY: daily
daily: build-all gen-tests ## Run the daily regression tier (100 tests: directed + seeded-random) -- some FAIL by design
	source $(VENV)/bin/activate && $(PYTHON) tools/regression.py daily --jobs $(JOBS)

.PHONY: random
random: build-all gen-tests ## Run the random regression tier (100 seeded-random tests) -- some FAIL by design
	source $(VENV)/bin/activate && $(PYTHON) tools/regression.py random --jobs $(JOBS)

.PHONY: cov-merge
cov-merge: venv ## Merge a regression run's coverage.dat files (usage: make cov-merge SUITE=smoke)
	$(PYTHON) tools/cov_merge.py $(SUITE)

.PHONY: profile
profile: venv ## Profile a regression run's wall-clock times/outliers (usage: make profile SUITE=smoke)
	$(PYTHON) tools/profiler.py $(SUITE)

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
