# Full-design RTL filelist -- every synthesizable source under rtl/, in
# dependency/compile order (packages and the tpe_verbosity.svh macro
# header first, since Verilator resolves the `TPE_LOG_* macros it
# defines via source order rather than an explicit `include -- see
# rtl/include/tpe_verbosity.svh's header comment).
#
# tpe_sram.sv and round_robin_arb.sv are included here even though
# neither is instantiated under tpe_top today: tpe_sram is a verified
# standalone/reusable block reserved for a future V2+ scheduler
# (rtl/top/tpe_top.sv's header comment), and round_robin_arb is a
# reusable common primitive (rtl/README.md) with no consumer yet. Both
# are still part of "the design" this filelist covers; a --top-module
# tpe_top compile simply won't elaborate them.
#
# Usage (run from repo root):
#   verilator --lint-only -Wall -f rtl/filelist.f --top-module tpe_top
#   verilator -cc -f rtl/filelist.f --top-module tpe_top
#
# Testbench compiles (verif/cocotb_tb/*/Makefile) intentionally keep
# their own narrower VERILOG_SOURCES lists (only the files each block
# needs, plus its harness/SVA/coverage) and don't source this file --
# see docs/flows/build_flow.md section 4.

rtl/include/tpe_verbosity.svh
rtl/include/tpe_pkg.sv
rtl/include/tpe_regs_pkg.sv

rtl/common/sync_fifo.sv
rtl/common/round_robin_arb.sv
rtl/common/dp_ram.sv

rtl/sram/tpe_sram.sv

rtl/matrix_engine/pe.sv
rtl/matrix_engine/mac_array.sv
rtl/matrix_engine/matrix_engine_ctrl.sv
rtl/matrix_engine/matrix_engine.sv

rtl/dma/tpe_dma.sv

rtl/command_processor/tpe_cmd_proc.sv

rtl/scheduler/tpe_scheduler.sv

rtl/pmu/tpe_pmu.sv

rtl/debug/tpe_debug.sv

rtl/top/tpe_top.sv
