"""Reusable monitor for a dp_ram-style sync port. See sync_port_item.py.

Samples every cycle (not just when en is asserted) because a scoreboard
maintaining a persistent shadow memory needs every cycle's operation, not
just the "interesting" ones.

Ctrl fields (en/we/strb/addr/wdata) are sampled at FallingEdge -- mid-cycle,
long after SyncPortDriver's post-RisingEdge update has settled and long
before its *next* update -- rather than at the same RisingEdge as rdata.
Sampling ctrl at the same RisingEdge as rdata looks tempting but is wrong:
SyncPortDriver retires the just-completed item and drives the *next* one
within the same simulation delta as that RisingEdge (before any ReadOnly
callback can fire), so a same-edge sample would pair the *next* operation's
ctrl fields with the *current* operation's rdata -- a one-operation
misalignment that a scoreboard with no persistent state (e.g. predicting a
simple counter's next value from its own last-observed value) self-corrects
every cycle and never notices, but which silently drops an operation's
effect for good in a scoreboard maintaining independent persistent state
(e.g. a shadow memory -- see verif/cocotb_tb/sram/scoreboard.py, where this
exact bug was first found and diagnosed). Sampling ctrl at FallingEdge and
rdata at the following RisingEdge keeps both fields describing the *same*
operation, with no shift for any consuming scoreboard to worry about.
"""
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge
from pyuvm import ConfigDB, uvm_analysis_port, uvm_monitor


class SyncPortTxn:
    __slots__ = ("en", "we", "strb", "addr", "wdata", "rdata")

    def __init__(self, en, we, strb, addr, wdata, rdata):
        self.en = en
        self.we = we
        self.strb = strb
        self.addr = addr
        self.wdata = wdata
        self.rdata = rdata


class SyncPortMonitor(uvm_monitor):
    def __init__(self, name, parent, port_prefix, clk_name="clk"):
        super().__init__(name, parent)
        self.port_prefix = port_prefix
        self.clk_name = clk_name

    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")
        self.clk = getattr(self.dut, self.clk_name)
        self.ap = uvm_analysis_port("ap", self)

    def _sig(self, name):
        return getattr(self.dut, f"{self.port_prefix}{name}")

    async def run_phase(self):
        while True:
            await FallingEdge(self.clk)
            en = int(self._sig("en").value)
            we = int(self._sig("we").value)
            strb = int(self._sig("strb").value)
            addr = int(self._sig("addr").value)
            wdata = int(self._sig("wdata").value)

            await RisingEdge(self.clk)
            await ReadOnly()
            rdata = int(self._sig("rdata").value)

            self.ap.write(SyncPortTxn(en, we, strb, addr, wdata, rdata))
