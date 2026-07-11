"""
Reusable pyuvm sequence item for anything shaped like rtl/common/dp_ram.sv's
per-port interface (en/we/strb/addr/wdata -> rdata). Any block whose
scratchpad-facing port follows this convention (Local SRAM today; the DMA
Engine and Matrix Engine's SRAM-facing ports in later milestones) reuses
this item + the driver/monitor/agent in this package instead of
reinventing per-block bus wiggling.
"""
from pyuvm import uvm_sequence_item


class SyncPortItem(uvm_sequence_item):
    def __init__(self, name="SyncPortItem", en=0, we=0, strb=0, addr=0, wdata=0):
        super().__init__(name)
        self.en = en
        self.we = we
        self.strb = strb
        self.addr = addr
        self.wdata = wdata

    def __str__(self):
        return (
            f"en={self.en} we={self.we} strb=0x{self.strb:x} "
            f"addr={self.addr} wdata=0x{self.wdata:x}"
        )
