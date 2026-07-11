"""
Local SRAM (Local Scratchpad) testbench -- the first real block testbench,
establishing the reusable pyuvm pattern (SyncPortAgent/Driver/Monitor from
verif/cocotb_tb/env/) every later block subclasses or reuses directly.

Two tests:
  sram_sanity_test  -- directed golden-path (the "sanity" tier)
  sram_random_test  -- constrained-random stress on both ports concurrently
                       (a standalone-runnable preview of what M6's daily/
                       random regressions will scale up to 100 tests each)
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from pyuvm import ConfigDB

from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest
from verif.cocotb_tb.sram.env import SramEnv
from verif.cocotb_tb.sram.sequences import SramDirectedSeq, SramRandomSeq

SRAM_DEPTH = 4096
ROW_BYTES = 16


class SramTestBase(TpeBaseTest):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = SramEnv("env", self, depth=SRAM_DEPTH, row_bytes=ROW_BYTES)


class SramSanityTest(SramTestBase):
    async def run_test_body(self):
        seq = SramDirectedSeq()
        await seq.start(self.env.agent_a.sequencer)


class SramRandomTest(SramTestBase):
    # Stays within [0, 4090) -- see SramDirectedSeq's reservation note.
    async def run_test_body(self):
        from tools.common.seed import get_seed
        base_seed = get_seed(1)
        seq_a = SramRandomSeq("seq_a", addr_lo=0, addr_hi=2000, n_ops=150, seed=base_seed)
        seq_b = SramRandomSeq("seq_b", addr_lo=2000, addr_hi=4000, n_ops=150, seed=base_seed + 1000)
        task_a = cocotb.start_soon(seq_a.start(self.env.agent_a.sequencer))
        task_b = cocotb.start_soon(seq_b.start(self.env.agent_b.sequencer))
        await task_a
        await task_b


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # cocotb's Clock produces its first 0->1 transition at t=0, which counts
    # as a valid RisingEdge trigger. Without settling past it here, a driver
    # racing ahead of the monitor at that very first edge can drive a
    # second item before the monitor ever samples the first one (there is
    # no reset signal on this DUT to naturally absorb this, unlike blocks
    # that have one). Two edges is enough margin; see the SRAM testbench's
    # discovery notes in docs/verification/test_plan.md if this regresses.
    for _ in range(2):
        await RisingEdge(dut.clk)
    # Move firmly past the settling edge's own reaction window (a bare
    # RisingEdge callback registered in the same delta as an edge can still
    # observe that same edge in cocotb) before pyuvm's components start
    # their own await RisingEdge loops, so driver and monitor agree on
    # which edge is "next."
    await Timer(1, units="ns")


@cocotb.test()
async def sram_sanity_test(dut):
    await _start_clock(dut)
    await pyuvm_run_test("SramSanityTest")


@cocotb.test()
async def sram_random_test(dut):
    await _start_clock(dut)
    await pyuvm_run_test("SramRandomTest")


async def pyuvm_run_test(test_name):
    import pyuvm
    await pyuvm.uvm_root().run_test(test_name)
