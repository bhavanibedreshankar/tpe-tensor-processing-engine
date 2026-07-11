import random

from pyuvm import uvm_sequence

from verif.cocotb_tb.env.sync_port_item import SyncPortItem


class SramDirectedSeq(uvm_sequence):
    """Golden-path sanity: a handful of hand-picked writes, read back on the
    same port. Human-verifiable by inspection, run standalone for debug."""

    # Addresses 4090-4095 are reserved for this directed test and never
    # touched by SramRandomSeq (see test_sram.py) so the two tests can share
    # one simulation process (cocotb runs all discovered tests against the
    # same persistent DUT memory, which has no reset) without one test's
    # writes corrupting the other's fresh-shadow assumption.
    def __init__(self, name="SramDirectedSeq"):
        super().__init__(name)
        self.ops = [
            (4090, 0xFFFF, 0x0102030405060708090A0B0C0D0E0F10),
            (4091, 0x00FF, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF),
            (4092, 0xFFFF, 0x00000000000000000000000000000000),
            (4095, 0xFFFF, 0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF),
        ]

    async def body(self):
        for addr, strb, wdata in self.ops:
            item = SyncPortItem(en=1, we=1, strb=strb, addr=addr, wdata=wdata)
            await self.start_item(item)
            await self.finish_item(item)
        for addr, _strb, _wdata in self.ops:
            item = SyncPortItem(en=1, we=0, strb=0, addr=addr, wdata=0)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)


class SramRandomSeq(uvm_sequence):
    """Constrained-random writes/reads confined to [addr_lo, addr_hi) so two
    sequences run concurrently on the two ports never race on the same
    address (see rtl/common/dp_ram.sv: same-cycle cross-port writes to the
    same address are undefined by design)."""

    def __init__(self, name, addr_lo, addr_hi, n_ops=150, write_prob=0.6, seed=None):
        super().__init__(name)
        self.addr_lo = addr_lo
        self.addr_hi = addr_hi
        self.n_ops = n_ops
        self.write_prob = write_prob
        self.rng = random.Random(seed)

    async def body(self):
        for _ in range(self.n_ops):
            addr = self.rng.randint(self.addr_lo, self.addr_hi - 1)
            we = 1 if self.rng.random() < self.write_prob else 0
            if we:
                strb = self.rng.choice([0xFFFF, 0x00FF, 0xFF00, 0x0001, 0x8000, 0x5555])
                wdata = self.rng.getrandbits(128)
            else:
                strb = 0
                wdata = 0
            item = SyncPortItem(en=1, we=we, strb=strb, addr=addr, wdata=wdata)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)
