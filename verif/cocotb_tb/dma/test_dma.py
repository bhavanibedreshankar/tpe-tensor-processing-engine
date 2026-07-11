"""
DMA Engine testbench. Preloads DDR/SRAM via backdoor SyncPortAgent access
(see dma_test_harness.sv), drives the descriptor control signals directly
(start/desc_mem_addr/desc_sram_addr/desc_len/desc_dir -- this standalone
interface is superseded by the real Command Processor register interface
in M4), waits for done/error, and checks the touched rows against the C++
golden model.

Addressing convention (matches rtl/dma/tpe_dma.sv): desc_mem_addr is a
*byte* address into DDR (AXI convention); desc_sram_addr is a *row* index
into the SRAM scratchpad (dp_ram convention, matching tpe_sram.sv
directly); desc_len is in bytes and must be a whole number of 16-byte rows.
"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from pyuvm import ConfigDB

from verif.cocotb_tb.dma.env import DmaEnv
from verif.cocotb_tb.dma.sequences import read_rows, write_rows
from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest

ROW_BYTES = 16
DDR_DEPTH = 256
SRAM_DEPTH = 4096  # fixed by tpe_pkg::SRAM_DEPTH, not overridable per-instance


async def run_dma(dut, env, mem_row, sram_row, n_rows, dir_sram_to_ddr, label):
    dut.desc_mem_addr.value = mem_row * ROW_BYTES
    dut.desc_sram_addr.value = sram_row
    dut.desc_len.value = n_rows * ROW_BYTES
    dut.desc_dir.value = 1 if dir_sram_to_ddr else 0
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    cycles = 0
    while int(dut.done.value) != 1 and int(dut.error.value) != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < 5000, f"[{label}] dma never asserted done/error"

    if int(dut.error.value) == 1:
        return "error"

    env.scoreboard.apply_dma(mem_row, sram_row, n_rows, dir_sram_to_ddr, label)

    if dir_sram_to_ddr:
        addrs = list(range(mem_row, mem_row + n_rows))
        rtl_rows = await read_rows(env.agent_ddr, env.ddr_collector, addrs)
        for a in addrs:
            env.scoreboard.check_row("ddr", a, rtl_rows[a], label=label)
    else:
        addrs = list(range(sram_row, sram_row + n_rows))
        rtl_rows = await read_rows(env.agent_sram, env.sram_collector, addrs)
        for a in addrs:
            env.scoreboard.check_row("sram", a, rtl_rows[a], label=label)

    await RisingEdge(dut.clk)
    return "done"


class DmaTestBase(TpeBaseTest):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = DmaEnv("env", self, ddr_depth=DDR_DEPTH, sram_depth=SRAM_DEPTH, row_bytes=ROW_BYTES)


class DmaSanityTest(DmaTestBase):
    async def run_test_body(self):
        rng = random.Random(1)
        ddr_rows = {i: rng.getrandbits(128) for i in range(4)}
        await write_rows(self.env.agent_ddr.sequencer, ddr_rows)
        for row, value in ddr_rows.items():
            self.env.scoreboard.record_ddr_write(row, value)

        status = await run_dma(cocotb.top, self.env, mem_row=0, sram_row=10, n_rows=4, dir_sram_to_ddr=False,
                                label="sanity_ddr_to_sram")
        assert status == "done"

        status = await run_dma(cocotb.top, self.env, mem_row=50, sram_row=10, n_rows=4, dir_sram_to_ddr=True,
                                label="sanity_sram_to_ddr")
        assert status == "done"


class DmaRandomTest(DmaTestBase):
    async def run_test_body(self):
        from tools.common.seed import get_seed
        rng = random.Random(get_seed(11))
        for i in range(10):
            dir_sram_to_ddr = rng.choice([False, True])
            n_rows = rng.randint(1, 40)  # exercises multi-burst transfers (> MAX_BURST_BEATS=16)
            mem_row = rng.randint(0, DDR_DEPTH - n_rows - 1)
            sram_row = rng.randint(0, 512 - n_rows - 1)

            if not dir_sram_to_ddr:
                rows = {mem_row + j: rng.getrandbits(128) for j in range(n_rows)}
                await write_rows(self.env.agent_ddr.sequencer, rows)
                for row, value in rows.items():
                    self.env.scoreboard.record_ddr_write(row, value)
            else:
                rows = {sram_row + j: rng.getrandbits(128) for j in range(n_rows)}
                await write_rows(self.env.agent_sram.sequencer, rows)
                for row, value in rows.items():
                    self.env.scoreboard.record_sram_write(row, value)

            status = await run_dma(cocotb.top, self.env, mem_row, sram_row, n_rows, dir_sram_to_ddr, f"random{i}")
            assert status == "done"


class DmaMultiBurstWriteTest(DmaTestBase):
    """Directed: n_rows=17 = MAX_BURST_BEATS(16) + 1 trailing beat, SRAM->DDR.
    Deterministically exercises the write-side multi-burst continuation
    (first burst 16 beats, second burst the trailing 1 beat) regardless of
    what DmaRandomTest's seed happens to roll -- see
    docs/verification/bug_list.md for the bug this is specifically
    targeting."""

    async def run_test_body(self):
        rng = random.Random(99)
        n_rows = 17
        rows = {j: rng.getrandbits(128) for j in range(n_rows)}
        await write_rows(self.env.agent_sram.sequencer, rows)
        for row, value in rows.items():
            self.env.scoreboard.record_sram_write(row, value)

        status = await run_dma(cocotb.top, self.env, mem_row=0, sram_row=0, n_rows=n_rows,
                                dir_sram_to_ddr=True, label="multiburst17")
        assert status == "done"


class DmaErrorTest(DmaTestBase):
    async def run_test_body(self):
        # desc_len not a multiple of ROW_BYTES -> misaligned, must error.
        # run_dma() always sets desc_len = n_rows*ROW_BYTES (aligned), so
        # drive the misaligned case directly instead.
        dut = cocotb.top
        dut.desc_mem_addr.value = 0
        dut.desc_sram_addr.value = 0
        dut.desc_len.value = 17  # not a multiple of 16
        dut.desc_dir.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cycles = 0
        while int(dut.done.value) != 1 and int(dut.error.value) != 1:
            await RisingEdge(dut.clk)
            cycles += 1
            assert cycles < 100, "dma never flagged the misaligned-length error"
        assert int(dut.error.value) == 1, "misaligned length should raise error, not done"


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
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
async def dma_sanity_test(dut):
    await _run("DmaSanityTest", dut)


@cocotb.test()
async def dma_random_test(dut):
    await _run("DmaRandomTest", dut)


@cocotb.test()
async def dma_multiburst_write_test(dut):
    await _run("DmaMultiBurstWriteTest", dut)


@cocotb.test()
async def dma_error_test(dut):
    await _run("DmaErrorTest", dut)
