"""Reusable agent bundling a sequencer + SyncPortDriver + SyncPortMonitor
for one dp_ram-style port. See sync_port_item.py."""
from pyuvm import uvm_agent, uvm_sequencer

from verif.cocotb_tb.env.sync_port_driver import SyncPortDriver
from verif.cocotb_tb.env.sync_port_monitor import SyncPortMonitor


class SyncPortAgent(uvm_agent):
    def __init__(self, name, parent, port_prefix, clk_name="clk"):
        super().__init__(name, parent)
        self.port_prefix = port_prefix
        self.clk_name = clk_name

    def build_phase(self):
        self.sequencer = uvm_sequencer("sequencer", self)
        self.driver = SyncPortDriver("driver", self, self.port_prefix, self.clk_name)
        self.monitor = SyncPortMonitor("monitor", self, self.port_prefix, self.clk_name)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.sequencer.seq_item_export)
