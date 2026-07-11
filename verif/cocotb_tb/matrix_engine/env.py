from pyuvm import uvm_env

from verif.cocotb_tb.env.row_collector import RowCollector
from verif.cocotb_tb.env.sync_port_agent import SyncPortAgent
from verif.cocotb_tb.matrix_engine.scoreboard import MatmulScoreboard


class MatrixEngineEnv(uvm_env):
    def build_phase(self):
        self.agent_weight = SyncPortAgent("agent_weight", self, "wbuf_a_")
        self.agent_act = SyncPortAgent("agent_act", self, "abuf_a_")
        self.agent_seed = SyncPortAgent("agent_seed", self, "sbuf_a_")
        self.agent_out = SyncPortAgent("agent_out", self, "obuf_a_")
        self.out_collector = RowCollector("out_collector", self)
        self.scoreboard = MatmulScoreboard("scoreboard", self)

    def connect_phase(self):
        self.agent_out.monitor.ap.connect(self.out_collector.analysis_export)
