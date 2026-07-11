"""
Standalone tpe_debug testbench: drives the real AXI4-Lite MMIO port with
Axi4LiteDriver and drives the scheduler-completion feed
(sched_done_valid/tag/status/opcode) directly from Python -- tpe_debug
doesn't need a real Scheduler behind it to verify its own trace-FIFO/
error-latch logic, only believable completion pulses on those four wires.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from verif.cocotb_tb.env.axi4_lite_driver import Axi4LiteDriver
from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest
from verif.cocotb_tb.env.tpe_regs import (
    DEBUG_CTRL_ADDR,
    DEBUG_CTRL_TRACE_ENABLE_LSB,
    DEBUG_TRACE_STATUS_ADDR,
    DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB,
    DEBUG_TRACE_STATUS_TRACE_COUNT_LSB,
    DEBUG_TRACE_STATUS_TRACE_COUNT_MASK,
    DEBUG_TRACE_RDATA_ADDR,
    DEBUG_ERROR_CODE_ADDR,
    DEBUG_ERROR_TAG_ADDR,
)

# tpe_pkg::cmd_opcode_e / cmd_status_e subset used by these tests
CMD_MATMUL = 0x3
CMD_STORE = 0x4
STAT_OK = 0
STAT_BAD_DIM = 2
STAT_MEM_ERROR = 4


async def push_completion(dut, opcode, tag, status):
    dut.sched_done_opcode.value = opcode
    dut.sched_done_tag.value = tag
    dut.sched_done_status.value = status
    dut.sched_done_valid.value = 1
    await RisingEdge(dut.clk)
    dut.sched_done_valid.value = 0
    await RisingEdge(dut.clk)


def trace_count(status_word):
    return (status_word >> DEBUG_TRACE_STATUS_TRACE_COUNT_LSB) & (
        DEBUG_TRACE_STATUS_TRACE_COUNT_MASK >> DEBUG_TRACE_STATUS_TRACE_COUNT_LSB
    )


class TracePopTest(TpeBaseTest):
    """Push two completions, check TRACE_STATUS.TRACE_COUNT, then pop both
    via TRACE_RDATA and check the opcode/tag/status packing round-trips."""

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")

        status = await axi.read(DEBUG_TRACE_STATUS_ADDR)
        assert (status >> DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB) & 1, "trace should start empty"

        await axi.write(DEBUG_CTRL_ADDR, 1 << DEBUG_CTRL_TRACE_ENABLE_LSB)

        await push_completion(dut, opcode=CMD_MATMUL, tag=0x123, status=STAT_OK)
        await push_completion(dut, opcode=CMD_STORE, tag=0x456, status=STAT_BAD_DIM)

        status = await axi.read(DEBUG_TRACE_STATUS_ADDR)
        assert trace_count(status) == 2, f"trace count={trace_count(status)}, want 2"

        e0 = await axi.read(DEBUG_TRACE_RDATA_ADDR)
        assert (e0 & 0xF, (e0 >> 4) & 0xFFF, (e0 >> 16) & 0x7) == (CMD_MATMUL, 0x123, STAT_OK), (
            f"entry0={e0:#x}"
        )

        e1 = await axi.read(DEBUG_TRACE_RDATA_ADDR)
        assert (e1 & 0xF, (e1 >> 4) & 0xFFF, (e1 >> 16) & 0x7) == (CMD_STORE, 0x456, STAT_BAD_DIM), (
            f"entry1={e1:#x}"
        )

        status = await axi.read(DEBUG_TRACE_STATUS_ADDR)
        assert (status >> DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB) & 1, "trace should be empty after popping both"


class ErrorLatchTest(TpeBaseTest):
    """ERROR_CODE/ERROR_TAG only latch on a non-STAT_OK completion, and hold
    the most recent one."""

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")

        await push_completion(dut, opcode=CMD_MATMUL, tag=0x11, status=STAT_OK)
        code = await axi.read(DEBUG_ERROR_CODE_ADDR)
        tag = await axi.read(DEBUG_ERROR_TAG_ADDR)
        assert code == 0 and tag == 0, f"error latched on a STAT_OK completion: code={code} tag={tag:#x}"

        await push_completion(dut, opcode=CMD_STORE, tag=0x22, status=STAT_MEM_ERROR)
        code = await axi.read(DEBUG_ERROR_CODE_ADDR)
        tag = await axi.read(DEBUG_ERROR_TAG_ADDR)
        assert code == STAT_MEM_ERROR and tag == 0x22, (
            f"error not latched correctly: code={code} tag={tag:#x}"
        )

        await push_completion(dut, opcode=CMD_MATMUL, tag=0x33, status=STAT_BAD_DIM)
        code = await axi.read(DEBUG_ERROR_CODE_ADDR)
        tag = await axi.read(DEBUG_ERROR_TAG_ADDR)
        assert code == STAT_BAD_DIM and tag == 0x33, (
            f"error latch didn't update to the most recent error: code={code} tag={tag:#x}"
        )


class TraceDisabledTest(TpeBaseTest):
    """CTRL.TRACE_ENABLE=0 (reset default): completions don't get pushed,
    but ERROR_CODE/ERROR_TAG still latch (independent of trace)."""

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")

        await push_completion(dut, opcode=CMD_MATMUL, tag=0x1, status=STAT_BAD_DIM)

        status = await axi.read(DEBUG_TRACE_STATUS_ADDR)
        assert (status >> DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB) & 1, "trace should stay empty while TRACE_ENABLE=0"

        code = await axi.read(DEBUG_ERROR_CODE_ADDR)
        assert code == STAT_BAD_DIM, f"error latch should still fire while TRACE_ENABLE=0: code={code}"


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.sched_done_valid.value = 0
    dut.sched_done_tag.value = 0
    dut.sched_done_status.value = 0
    dut.sched_done_opcode.value = 0
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
async def trace_pop_test(dut):
    await _run("TracePopTest", dut)


@cocotb.test()
async def error_latch_test(dut):
    await _run("ErrorLatchTest", dut)


@cocotb.test()
async def trace_disabled_test(dut):
    await _run("TraceDisabledTest", dut)
