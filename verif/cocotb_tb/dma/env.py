from pyuvm import uvm_env

from verif.cocotb_tb.dma.scoreboard import DmaScoreboard
from verif.cocotb_tb.env.row_collector import RowCollector
from verif.cocotb_tb.env.sync_port_agent import SyncPortAgent


class DmaEnv(uvm_env):
    def __init__(self, name, parent, ddr_depth, sram_depth, row_bytes=16):
        super().__init__(name, parent)
        self.ddr_depth = ddr_depth
        self.sram_depth = sram_depth
        self.row_bytes = row_bytes

    def build_phase(self):
        self.agent_sram = SyncPortAgent("agent_sram", self, "sram_tb_")
        self.agent_ddr = SyncPortAgent("agent_ddr", self, "ddr_tb_")
        self.sram_collector = RowCollector("sram_collector", self)
        self.ddr_collector = RowCollector("ddr_collector", self)
        self.scoreboard = DmaScoreboard(
            "scoreboard", self, ddr_depth=self.ddr_depth, sram_depth=self.sram_depth, row_bytes=self.row_bytes
        )

    def connect_phase(self):
        self.agent_sram.monitor.ap.connect(self.sram_collector.analysis_export)
        self.agent_ddr.monitor.ap.connect(self.ddr_collector.analysis_export)
