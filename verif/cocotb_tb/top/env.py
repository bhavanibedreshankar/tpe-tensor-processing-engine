from pyuvm import uvm_env

from verif.cocotb_tb.env.axi4_lite_driver import Axi4LiteDriver
from verif.cocotb_tb.env.row_collector import RowCollector
from verif.cocotb_tb.env.sync_port_agent import SyncPortAgent
from verif.cocotb_tb.top.scoreboard import TopScoreboard


class TopEnv(uvm_env):
    def __init__(self, name, parent, ddr_depth):
        super().__init__(name, parent)
        self.ddr_depth = ddr_depth

    def build_phase(self):
        self.agent_ddr = SyncPortAgent("agent_ddr", self, "ddr_tb_")
        self.ddr_collector = RowCollector("ddr_collector", self)
        self.scoreboard = TopScoreboard("scoreboard", self, ddr_depth=self.ddr_depth)

    def connect_phase(self):
        self.agent_ddr.monitor.ap.connect(self.ddr_collector.analysis_export)
