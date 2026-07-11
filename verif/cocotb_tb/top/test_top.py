"""
Top-level end-to-end testbench: drives the real host-facing AXI4-Lite MMIO
interface (rtl/top/tpe_top.sv -> rtl/command_processor/tpe_cmd_proc.sv),
exactly like real driver software would -- stage command fields, write
CMD_PUSH, poll (or wait on IRQ for) completion -- reproducing the
overview's canonical command sequence: load weights, load activations,
matmul, store result, per docs/architecture/tpe_architecture_spec.md
section 5 (V1 has no activation unit, so no ReLU step here).

ROWS=COLS=16 (the architecture's default array size, not M2's small 4x4
test config) because the STORE chunk-adapter's width math (out_buf row =
COLS*ACCUM_WIDTH = ObufChunksPerRow x AXI_DATA_WIDTH) only comes out to a
whole number of chunks at COLS=16 -- see rtl/top/tpe_top.sv's header
comment.
"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from pyuvm import ConfigDB

from verif.cocotb_tb.env.axi4_lite_driver import Axi4LiteDriver
from verif.cocotb_tb.env.tpe_regs import (
    CP_IRQ_ENABLE_ADDR,
    CP_IRQ_STATUS_ADDR,
    CP_IRQ_STATUS_CMD_DONE_LSB,
    PMU_CTRL_ADDR,
    PMU_CTRL_ENABLE_LSB,
    PMU_CYCLE_COUNT_ADDR,
    DEBUG_CTRL_ADDR,
    DEBUG_CTRL_TRACE_ENABLE_LSB,
    DEBUG_TRACE_RDATA_ADDR,
    DEBUG_ERROR_CODE_ADDR,
    DEBUG_ERROR_TAG_ADDR,
)
from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest
from verif.cocotb_tb.top.env import TopEnv
from verif.cocotb_tb.top.sequences import enable_cp, run_command, status_error, status_last_status

# tpe_pkg::cmd_opcode_e
CMD_NOP = 0x0
CMD_LOAD_WEIGHT = 0x1
CMD_LOAD_ACT = 0x2
CMD_MATMUL = 0x3
CMD_STORE = 0x4
CMD_BARRIER = 0x5
CMD_IRQ_TEST = 0xE

STAT_OK = 0

ROWS = 16
COLS = 16
DDR_DEPTH = 1024
ROW_BYTES = 16


async def preload_ddr(env, start_row, rows):
    """rows: list of 128-bit ints. Writes via the DDR backdoor agent."""
    from verif.cocotb_tb.dma.sequences import write_rows  # reuse M3's helper

    row_map = {start_row + i: v for i, v in enumerate(rows)}
    await write_rows(env.agent_ddr.sequencer, row_map)


def pack_row(values, field_width, n_fields):
    word = 0
    mask = (1 << field_width) - 1
    for i in range(n_fields):
        word |= (values[i] & mask) << (i * field_width)
    return word


class MatmulFlowTest(TpeBaseTest):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        rng = random.Random(42)

        dim_m, dim_k, dim_n = 4, 6, 5

        a_rows = [[rng.randint(-8, 8) for _ in range(dim_k)] for _ in range(dim_m)]
        b_rows = [[rng.randint(-8, 8) for _ in range(dim_n)] for _ in range(dim_k)]

        weight_start_row = 0
        act_start_row = 100
        store_start_row = 200

        weight_ddr_words = [pack_row(b_rows[k] + [0] * (COLS - dim_n), 8, COLS) for k in range(dim_k)]
        act_ddr_words = [pack_row(a_rows[m] + [0] * (ROWS - dim_k), 8, ROWS) for m in range(dim_m)]
        await preload_ddr(self.env, weight_start_row, weight_ddr_words)
        await preload_ddr(self.env, act_start_row, act_ddr_words)

        await enable_cp(axi)

        status = await run_command(dut, axi, dut.clk, CMD_LOAD_WEIGHT, tag=1,
                                     mem_addr=weight_start_row * ROW_BYTES, sram_addr=0, dim_k=dim_k)
        assert status_last_status(status) == STAT_OK, f"LOAD_WEIGHT status={status_last_status(status)}"

        status = await run_command(dut, axi, dut.clk, CMD_LOAD_ACT, tag=2,
                                     mem_addr=act_start_row * ROW_BYTES, sram_addr=0, dim_m=dim_m)
        assert status_last_status(status) == STAT_OK, f"LOAD_ACT status={status_last_status(status)}"

        status = await run_command(dut, axi, dut.clk, CMD_MATMUL, tag=3,
                                     dim_m=dim_m, dim_k=dim_k, dim_n=dim_n)
        assert status_last_status(status) == STAT_OK, f"MATMUL status={status_last_status(status)}"

        status = await run_command(dut, axi, dut.clk, CMD_STORE, tag=4,
                                     mem_addr=store_start_row * ROW_BYTES, sram_addr=0, dim_m=dim_m)
        assert status_last_status(status) == STAT_OK, f"STORE status={status_last_status(status)}"

        from verif.cocotb_tb.dma.sequences import read_rows  # reuse M3's helper

        n_store_words = dim_m * 4
        addrs = list(range(store_start_row, store_start_row + n_store_words))
        rtl_words_map = await read_rows(self.env.agent_ddr, self.env.ddr_collector, addrs)
        rtl_words = [rtl_words_map[a] for a in addrs]

        c_matrix = self.env.scoreboard.golden_matmul(a_rows, b_rows, dim_m, dim_k, dim_n, label="flow")
        expected_words = self.env.scoreboard.expected_store_rows(c_matrix, dim_m, dim_n)
        self.env.scoreboard.check_store(expected_words, rtl_words, label="flow")


class ErrorHandlingTest(TpeBaseTest):
    """Exercises the administrative/error opcodes: NOP, BARRIER (immediate
    complete, no engine dispatch), an unrecognized opcode (STAT_BAD_OPCODE),
    and a MATMUL with dim_k exceeding the array's ROWS (STAT_BAD_DIM)."""

    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        await enable_cp(axi)

        status = await run_command(dut, axi, dut.clk, CMD_NOP, tag=10)
        assert status_last_status(status) == STAT_OK, f"NOP status={status_last_status(status)}"

        status = await run_command(dut, axi, dut.clk, CMD_BARRIER, tag=11)
        assert status_last_status(status) == STAT_OK, f"BARRIER status={status_last_status(status)}"

        BAD_OPCODE = 0x6  # reserved/unused in tpe_pkg::cmd_opcode_e
        status = await run_command(dut, axi, dut.clk, BAD_OPCODE, tag=12)
        assert status_last_status(status) == 1, f"bad opcode status={status_last_status(status)} (want STAT_BAD_OPCODE=1)"

        status = await run_command(dut, axi, dut.clk, CMD_MATMUL, tag=13, dim_m=1, dim_k=ROWS + 1, dim_n=1)
        assert status_last_status(status) == 2, f"bad dim status={status_last_status(status)} (want STAT_BAD_DIM=2)"


class MatmulFullWidthTest(TpeBaseTest):
    """Directed: dim_n == COLS exactly (the array's full physical width,
    a legitimate, exactly-fitting tile -- not an out-of-range one).
    MatmulFlowTest and DmaRandomTest-style fuzzing both stay comfortably
    under COLS, so only a directed boundary case like this one reliably
    exercises dim_n == COLS specifically. See docs/verification/bug_list.md
    if this fails."""

    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        rng = random.Random(5)
        await enable_cp(axi)

        dim_m, dim_k, dim_n = 2, 4, COLS  # dim_n at the exact array width
        a_rows = [[rng.randint(-8, 8) for _ in range(dim_k)] for _ in range(dim_m)]
        b_rows = [[rng.randint(-8, 8) for _ in range(dim_n)] for _ in range(dim_k)]

        weight_ddr_words = [pack_row(b_rows[k], 8, COLS) for k in range(dim_k)]
        act_ddr_words = [pack_row(a_rows[m] + [0] * (ROWS - dim_k), 8, ROWS) for m in range(dim_m)]
        await preload_ddr(self.env, 0, weight_ddr_words)
        await preload_ddr(self.env, 100, act_ddr_words)

        status = await run_command(dut, axi, dut.clk, CMD_LOAD_WEIGHT, tag=20, mem_addr=0, sram_addr=0, dim_k=dim_k)
        assert status_last_status(status) == STAT_OK

        status = await run_command(dut, axi, dut.clk, CMD_LOAD_ACT, tag=21, mem_addr=100 * ROW_BYTES, sram_addr=0, dim_m=dim_m)
        assert status_last_status(status) == STAT_OK

        status = await run_command(dut, axi, dut.clk, CMD_MATMUL, tag=22, dim_m=dim_m, dim_k=dim_k, dim_n=dim_n)
        assert status_last_status(status) == STAT_OK, (
            f"MATMUL with dim_n==COLS({COLS}) status={status_last_status(status)}, want STAT_OK"
        )


class IrqIndependentClearTest(TpeBaseTest):
    """Directed: CMD_DONE and CMD_ERROR must be independently write-1-to-
    clear. Forces both bits set (one erroring command sets both -- see
    tpe_cmd_proc.sv), then clears only CMD_ERROR and checks CMD_DONE stays
    set. See docs/verification/bug_list.md if this fails."""

    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        await enable_cp(axi)

        BAD_OPCODE = 0x6
        status = await run_command(dut, axi, dut.clk, BAD_OPCODE, tag=30)
        assert status_last_status(status) == 1  # STAT_BAD_OPCODE

        irq_status = await axi.read(CP_IRQ_STATUS_ADDR)
        assert irq_status & 0x3 == 0x3, f"expected both CMD_DONE and CMD_ERROR set, got {irq_status:#x}"

        await axi.write(CP_IRQ_STATUS_ADDR, 0b10)  # clear CMD_ERROR only
        irq_status = await axi.read(CP_IRQ_STATUS_ADDR)
        assert irq_status & 0x3 == 0b01, (
            f"clearing CMD_ERROR alone should leave CMD_DONE set: got {irq_status:#x}, want 0b01"
        )


class PmuDebugIntegrationTest(TpeBaseTest):
    """M5: proves the real top-level host MMIO address router (rtl/top/
    tpe_top.sv) actually reaches PMU and Debug, not just Command Processor
    -- something no standalone tpe_pmu/tpe_debug testbench can exercise on
    its own, since those drive the event/completion inputs directly rather
    than through a real Scheduler + router. Runs two real commands (one
    OK, one bad-opcode) over the real AXI4-Lite MMIO port and checks PMU's
    cycle counter advanced and Debug's trace/error registers captured both
    completions correctly."""

    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        await enable_cp(axi)

        await axi.write(PMU_CTRL_ADDR, 1 << PMU_CTRL_ENABLE_LSB)
        await axi.write(DEBUG_CTRL_ADDR, 1 << DEBUG_CTRL_TRACE_ENABLE_LSB)

        status = await run_command(dut, axi, dut.clk, CMD_NOP, tag=0x50)
        assert status_last_status(status) == STAT_OK

        BAD_OPCODE = 0x6
        status = await run_command(dut, axi, dut.clk, BAD_OPCODE, tag=0x51)
        assert status_last_status(status) == 1  # STAT_BAD_OPCODE

        cycles = await axi.read(PMU_CYCLE_COUNT_ADDR)
        assert cycles > 0, f"PMU_CYCLE_COUNT={cycles} after two commands, want >0 (router not reaching PMU?)"

        e0 = await axi.read(DEBUG_TRACE_RDATA_ADDR)
        assert (e0 & 0xF, (e0 >> 4) & 0xFFF, (e0 >> 16) & 0x7) == (CMD_NOP, 0x50, STAT_OK), (
            f"debug trace entry0={e0:#x}, want (opcode=NOP, tag=0x50, status=OK) "
            "(router not reaching Debug?)"
        )
        e1 = await axi.read(DEBUG_TRACE_RDATA_ADDR)
        assert (e1 & 0xF, (e1 >> 4) & 0xFFF, (e1 >> 16) & 0x7) == (BAD_OPCODE, 0x51, 1), (
            f"debug trace entry1={e1:#x}, want (opcode=0x6, tag=0x51, status=BAD_OPCODE)"
        )

        error_code = await axi.read(DEBUG_ERROR_CODE_ADDR)
        error_tag = await axi.read(DEBUG_ERROR_TAG_ADDR)
        assert error_code == 1 and error_tag == 0x51, (
            f"debug error latch: code={error_code} tag={error_tag:#x}, want code=1(BAD_OPCODE) tag=0x51"
        )


class IrqTest(TpeBaseTest):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = TopEnv("env", self, ddr_depth=DDR_DEPTH)

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")

        await enable_cp(axi)
        await axi.write(CP_IRQ_ENABLE_ADDR, 1 << CP_IRQ_STATUS_CMD_DONE_LSB)

        from verif.cocotb_tb.top.sequences import push_command
        await push_command(axi, CMD_IRQ_TEST, tag=7, sram_addr=0, mem_addr=0, dim_m=0, dim_k=0, dim_n=0)

        cycles = 0
        while int(dut.irq.value) != 1:
            await RisingEdge(dut.clk)
            cycles += 1
            assert cycles < 2000, "irq never asserted after CMD_IRQ_TEST"

        irq_status = await axi.read(CP_IRQ_STATUS_ADDR)
        assert (irq_status >> CP_IRQ_STATUS_CMD_DONE_LSB) & 1, "IRQ_STATUS.CMD_DONE not set"

        await axi.write(CP_IRQ_STATUS_ADDR, 1 << CP_IRQ_STATUS_CMD_DONE_LSB)
        await RisingEdge(dut.clk)
        assert int(dut.irq.value) == 0, "irq did not deassert after W1C clear"


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _run(test_name, dut):
    await _start_clock(dut)
    import pyuvm
    await pyuvm.uvm_root().run_test(test_name)


@cocotb.test()
async def matmul_flow_test(dut):
    await _run("MatmulFlowTest", dut)


@cocotb.test()
async def irq_test(dut):
    await _run("IrqTest", dut)


@cocotb.test()
async def error_handling_test(dut):
    await _run("ErrorHandlingTest", dut)


@cocotb.test()
async def matmul_full_width_test(dut):
    await _run("MatmulFullWidthTest", dut)


@cocotb.test()
async def irq_independent_clear_test(dut):
    await _run("IrqIndependentClearTest", dut)


@cocotb.test()
async def pmu_debug_integration_test(dut):
    await _run("PmuDebugIntegrationTest", dut)
