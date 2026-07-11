from pyuvm import uvm_env

from verif.cocotb_tb.env.sync_port_agent import SyncPortAgent
from verif.cocotb_tb.sram.scoreboard import SramScoreboard


class SramEnv(uvm_env):
    def __init__(self, name, parent, depth=4096, row_bytes=16):
        super().__init__(name, parent)
        self.depth = depth
        self.row_bytes = row_bytes

    def build_phase(self):
        self.agent_a = SyncPortAgent("agent_a", self, "a_")
        self.agent_b = SyncPortAgent("agent_b", self, "b_")
        self.scoreboard = SramScoreboard("scoreboard", self, depth=self.depth, row_bytes=self.row_bytes)

    def connect_phase(self):
        self.agent_a.monitor.ap.connect(self.scoreboard.fifo_a.analysis_export)
        self.agent_b.monitor.ap.connect(self.scoreboard.fifo_b.analysis_export)
