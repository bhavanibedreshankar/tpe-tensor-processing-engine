"""Reusable driver for a dp_ram-style sync port. See sync_port_item.py."""
from cocotb.triggers import RisingEdge
from pyuvm import ConfigDB, uvm_driver


class SyncPortDriver(uvm_driver):
    def __init__(self, name, parent, port_prefix, clk_name="clk"):
        super().__init__(name, parent)
        self.port_prefix = port_prefix
        self.clk_name = clk_name

    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")
        self.clk = getattr(self.dut, self.clk_name)

    def _sig(self, name):
        return getattr(self.dut, f"{self.port_prefix}{name}")

    async def run_phase(self):
        self._sig("en").value = 0
        self._sig("we").value = 0
        while True:
            item = await self.seq_item_port.get_next_item()
            self._sig("en").value = item.en
            self._sig("we").value = item.we
            self._sig("strb").value = item.strb
            self._sig("addr").value = item.addr
            self._sig("wdata").value = item.wdata
            await RisingEdge(self.clk)
            # Idle by default between items so gaps in the sequence don't
            # accidentally repeat the last op for extra cycles.
            self._sig("en").value = 0
            self._sig("we").value = 0
            self.seq_item_port.item_done()
