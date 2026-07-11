"""
Toolchain smoke test.

Not part of the TPE verification suite proper -- this is a throwaway
end-to-end check that cocotb + pyuvm + Verilator (DUT-side SVA + covergroup)
+ FST waveform dump all function together on this machine, using the
pyuvm class-based (driver/monitor/scoreboard/sequencer/sequence/env/test)
pattern that the real TPE testbenches will follow.
"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from pyuvm import (
    ConfigDB,
    uvm_component,
    uvm_driver,
    uvm_env,
    uvm_monitor,
    uvm_scoreboard,
    uvm_sequence,
    uvm_sequence_item,
    uvm_sequencer,
    uvm_test,
)
import pyuvm


class CounterItem(uvm_sequence_item):
    def __init__(self, name="CounterItem", en=1, load=0, load_value=0):
        super().__init__(name)
        self.en = en
        self.load = load
        self.load_value = load_value


class CounterSeq(uvm_sequence):
    """Randomized enable/load stimulus for N transactions."""

    def __init__(self, name="CounterSeq", n_items=64):
        super().__init__(name)
        self.n_items = n_items

    async def body(self):
        for _ in range(self.n_items):
            item = CounterItem(
                en=random.choice([0, 1, 1, 1]),
                load=1 if random.random() < 0.05 else 0,
                load_value=random.randint(0, 255),
            )
            await self.start_item(item)
            await self.finish_item(item)


class CounterDriver(uvm_driver):
    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")

    async def run_phase(self):
        while True:
            item = await self.seq_item_port.get_next_item()
            self.dut.en.value = item.en
            self.dut.load.value = item.load
            self.dut.load_value.value = item.load_value
            await RisingEdge(self.dut.clk)
            self.seq_item_port.item_done()


class CounterMonitor(uvm_monitor):
    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")
        self.ap = pyuvm.uvm_analysis_port("ap", self)

    async def run_phase(self):
        while True:
            await RisingEdge(self.dut.clk)
            en = int(self.dut.en.value)
            load = int(self.dut.load.value)
            load_value = int(self.dut.load_value.value)
            count = int(self.dut.count.value)
            self.ap.write((en, load, load_value, count))


class CounterScoreboard(uvm_scoreboard):
    """Predicts count[cycle] from (en, load, load_value)[cycle-1] and checks it."""

    def build_phase(self):
        self.fifo = pyuvm.uvm_tlm_analysis_fifo("fifo", self)
        self.get_port = pyuvm.uvm_get_port("get_port", self)
        self.predicted = None
        self.prev_inputs = None
        self.errors = 0
        self.checked = 0

    def connect_phase(self):
        self.get_port.connect(self.fifo.get_export)

    async def run_phase(self):
        while True:
            en, load, load_value, count = await self.get_port.get()
            if self.prev_inputs is not None:
                prev_en, prev_load, prev_load_value, prev_count = self.prev_inputs
                if prev_load:
                    expected = prev_load_value
                elif prev_en:
                    expected = (prev_count + 1) & 0xFF
                else:
                    expected = prev_count
                self.checked += 1
                if count != expected:
                    self.errors += 1
                    self.logger.error(
                        f"count mismatch: got {count}, expected {expected} "
                        f"(prev en={prev_en} load={prev_load} "
                        f"load_value={prev_load_value} count={prev_count})"
                    )
            self.prev_inputs = (en, load, load_value, count)

    def report_phase(self):
        self.logger.info(f"Smoke scoreboard checked {self.checked} cycles, {self.errors} errors")
        assert self.errors == 0, f"Smoke scoreboard saw {self.errors} mismatches"


class CounterEnv(uvm_env):
    def build_phase(self):
        self.seqr = uvm_sequencer("seqr", self)
        ConfigDB().set(None, "*", "SEQR", self.seqr)
        self.driver = CounterDriver.create("driver", self)
        self.monitor = CounterMonitor.create("monitor", self)
        self.scoreboard = CounterScoreboard.create("scoreboard", self)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)
        self.monitor.ap.connect(self.scoreboard.fifo.analysis_export)


class SmokeTest(uvm_test):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = CounterEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        seqr = ConfigDB().get(self, "", "SEQR")
        seq = CounterSeq("seq", n_items=128)
        await seq.start(seqr)
        self.drop_objection()


@cocotb.test()
async def smoke_toolchain_test(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.load.value = 0
    dut.load_value.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    await pyuvm.uvm_root().run_test("SmokeTest")
