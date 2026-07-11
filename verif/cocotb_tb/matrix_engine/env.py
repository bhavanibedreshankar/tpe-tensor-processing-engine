import pyuvm
from pyuvm import uvm_env

from verif.cocotb_tb.env.sync_port_agent import SyncPortAgent
from verif.cocotb_tb.matrix_engine.scoreboard import MatmulScoreboard


class OutputCollector(pyuvm.uvm_subscriber):
    """Collects {addr: rdata} from a SyncPortAgent's monitor for read
    transactions, so sequences.read_out_tile can pull results back out
    after issuing a batch of reads. See sync_port_monitor.py -- txn.rdata
    already corresponds to txn.addr in the same transaction, no reordering
    needed here."""

    def build_phase(self):
        self.collected = {}

    def write(self, txn):
        if txn.en and not txn.we:
            self.collected[txn.addr] = txn.rdata

    def clear(self):
        self.collected = {}


class MatrixEngineEnv(uvm_env):
    def build_phase(self):
        self.agent_weight = SyncPortAgent("agent_weight", self, "wbuf_a_")
        self.agent_act = SyncPortAgent("agent_act", self, "abuf_a_")
        self.agent_seed = SyncPortAgent("agent_seed", self, "sbuf_a_")
        self.agent_out = SyncPortAgent("agent_out", self, "obuf_a_")
        self.out_collector = OutputCollector("out_collector", self)
        self.scoreboard = MatmulScoreboard("scoreboard", self)

    def connect_phase(self):
        self.agent_out.monitor.ap.connect(self.out_collector.analysis_export)
