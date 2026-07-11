"""Backdoor row write/read helpers for the DMA testbench, driving a
SyncPortAgent connected to tpe_sram's or axi4_ddr_model's backdoor port."""
from pyuvm import uvm_sequence

from verif.cocotb_tb.env.sync_port_item import SyncPortItem


class _WriteRowsSeq(uvm_sequence):
    def __init__(self, name, rows):
        super().__init__(name)
        self.rows = rows  # dict[addr] = value_int

    async def body(self):
        for addr, value in self.rows.items():
            item = SyncPortItem(en=1, we=1, strb=0xFFFF, addr=addr, wdata=value)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)


class _ReadRowsSeq(uvm_sequence):
    def __init__(self, name, addrs):
        super().__init__(name)
        self.addrs = addrs

    async def body(self):
        for addr in self.addrs:
            item = SyncPortItem(en=1, we=0, strb=0, addr=addr, wdata=0)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)


async def write_rows(sequencer, rows):
    await _WriteRowsSeq("write_rows", rows).start(sequencer)


async def read_rows(agent, collector, addrs):
    collector.clear()
    await _ReadRowsSeq("read_rows", addrs).start(agent.sequencer)
    result = {}
    for addr in addrs:
        assert addr in collector.collected, f"no read observed for addr {addr}"
        result[addr] = collector.collected[addr]
    return result
