"""
Standalone tpe_pmu testbench: drives the real AXI4-Lite MMIO port with
Axi4LiteDriver (same driver test_top.py uses against the real Command
Processor) and drives the event inputs (mac_active/dma_wait/sched_stall/
sched_idle/dispatch_start/cmd_done_valid) directly from Python -- tpe_pmu
doesn't need a real Scheduler behind it to verify its own counter/register
logic, only believable event pulses on those six wires.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from verif.cocotb_tb.env.axi4_lite_driver import Axi4LiteDriver
from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest
from verif.cocotb_tb.env.tpe_regs import (
    PMU_CTRL_ADDR,
    PMU_CTRL_ENABLE_LSB,
    PMU_CTRL_RESET_COUNTERS_LSB,
    PMU_CYCLE_COUNT_ADDR,
    PMU_MAC_ACTIVE_COUNT_ADDR,
    PMU_DMA_WAIT_COUNT_ADDR,
    PMU_SCHED_STALL_COUNT_ADDR,
    PMU_IDLE_COUNT_ADDR,
    PMU_CMD_LATENCY_LAST_ADDR,
)


class CounterBasicsTest(TpeBaseTest):
    """ENABLE gating, per-event counters, and RESET_COUNTERS."""

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")

        c0 = await axi.read(PMU_CYCLE_COUNT_ADDR)
        assert c0 == 0, f"cycle_count before ENABLE={c0}, want 0"

        for _ in range(5):
            await RisingEdge(dut.clk)
        c_disabled = await axi.read(PMU_CYCLE_COUNT_ADDR)
        assert c_disabled == 0, f"cycle_count advanced while ENABLE=0: {c_disabled}"

        await axi.write(PMU_CTRL_ADDR, 1 << PMU_CTRL_ENABLE_LSB)

        for _ in range(10):
            await RisingEdge(dut.clk)

        dut.mac_active.value = 1
        dut.dma_wait.value = 1
        dut.sched_idle.value = 1
        for _ in range(4):
            await RisingEdge(dut.clk)
        dut.mac_active.value = 0
        dut.dma_wait.value = 0
        dut.sched_idle.value = 0
        await RisingEdge(dut.clk)

        # Freeze counting (ENABLE=0) before taking exact readings -- these
        # are live free-running counters, so a read issued while still
        # counting would see extra ticks accrued during the read
        # transaction's own AXI4-Lite handshake cycles, not a meaningful
        # comparison.
        await axi.write(PMU_CTRL_ADDR, 0)

        cyc = await axi.read(PMU_CYCLE_COUNT_ADDR)
        assert cyc >= 14, f"cycle_count={cyc}, want >=14 (10 + 4 event cycles)"

        mac = await axi.read(PMU_MAC_ACTIVE_COUNT_ADDR)
        dma = await axi.read(PMU_DMA_WAIT_COUNT_ADDR)
        idle = await axi.read(PMU_IDLE_COUNT_ADDR)
        assert mac == 4, f"mac_active_count={mac}, want 4"
        assert dma == 4, f"dma_wait_count={dma}, want 4"
        assert idle == 4, f"idle_count={idle}, want 4"

        stall = await axi.read(PMU_SCHED_STALL_COUNT_ADDR)
        assert stall == 0, f"sched_stall_count={stall}, want 0 (never asserted)"

        await axi.write(PMU_CTRL_ADDR, (1 << PMU_CTRL_ENABLE_LSB) | (1 << PMU_CTRL_RESET_COUNTERS_LSB))
        await RisingEdge(dut.clk)
        cyc2 = await axi.read(PMU_CYCLE_COUNT_ADDR)
        mac2 = await axi.read(PMU_MAC_ACTIVE_COUNT_ADDR)
        assert cyc2 == 0 and mac2 == 0, f"counters after RESET_COUNTERS: cycle={cyc2} mac={mac2}, want 0/0"

        await axi.write(PMU_CTRL_ADDR, 1 << PMU_CTRL_ENABLE_LSB)
        for _ in range(3):
            await RisingEdge(dut.clk)
        cyc3 = await axi.read(PMU_CYCLE_COUNT_ADDR)
        assert cyc3 >= 3, f"cycle_count after releasing RESET_COUNTERS={cyc3}, want >=3 (counting resumed)"


class LatencyTest(TpeBaseTest):
    """Directed: drive a synthetic dispatch_start..cmd_done_valid window of
    a known N cycles and check CMD_LATENCY_LAST reads back N. See
    docs/verification/bug_list.md bug #7 if this fails -- the RTL currently
    undercounts by exactly 1 (a same-cycle nonblocking-assignment ordering
    bug: the completion cycle's own increment hasn't landed in
    latency_ctr_q yet when cmd_latency_last_q captures it)."""

    async def run_test_body(self):
        dut = cocotb.top
        axi = Axi4LiteDriver(dut, dut.clk, "s_")
        await axi.write(PMU_CTRL_ADDR, 1 << PMU_CTRL_ENABLE_LSB)

        n_cycles = 5
        dut.dispatch_start.value = 1
        await RisingEdge(dut.clk)
        dut.dispatch_start.value = 0
        for _ in range(n_cycles - 2):
            await RisingEdge(dut.clk)
        dut.cmd_done_valid.value = 1
        await RisingEdge(dut.clk)
        dut.cmd_done_valid.value = 0
        await RisingEdge(dut.clk)

        latency = await axi.read(PMU_CMD_LATENCY_LAST_ADDR)
        assert latency == n_cycles, (
            f"CMD_LATENCY_LAST={latency}, want {n_cycles} "
            f"(see docs/verification/bug_list.md bug #7)"
        )


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.mac_active.value = 0
    dut.dma_wait.value = 0
    dut.sched_stall.value = 0
    dut.sched_idle.value = 0
    dut.dispatch_start.value = 0
    dut.cmd_done_valid.value = 0
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
async def counter_basics_test(dut):
    await _run("CounterBasicsTest", dut)


@cocotb.test()
async def latency_test(dut):
    await _run("LatencyTest", dut)
