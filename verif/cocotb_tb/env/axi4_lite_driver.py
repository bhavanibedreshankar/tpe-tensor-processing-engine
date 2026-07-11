"""
Reusable direct (non-pyuvm-sequenced) AXI4-Lite driver: a test calls
await axi.write(addr, data) / await axi.read(addr) directly rather than
going through a sequencer -- MMIO register pokes don't need randomized
stimulus generation the way bulk data movement does, so the extra
sequence-item ceremony isn't worth it here (contrast with
verif/cocotb_tb/env/sync_port_*.py, which does warrant it).

Matches rtl/command_processor/tpe_cmd_proc.sv's V1 simplification of
requiring AWVALID+WVALID together (see that file's header comment) --
this driver always presents them on the same cycle. Reusable for any
future AXI4-Lite-visible block (M5's PMU/Debug), not just the Command
Processor.

Samples signals with a plain post-RisingEdge read (no ReadOnly): a write
right after ReadOnly() is illegal in cocotb (still inside the read-only
phase), and every other block's polling loop in this repo
(test_dma.py/test_matrix_engine.py) already uses this same plain-read
pattern without issue.
"""
from cocotb.triggers import RisingEdge


class Axi4LiteDriver:
    def __init__(self, dut, clk, prefix="s_"):
        self.dut = dut
        self.clk = clk
        self.prefix = prefix

    def _sig(self, name):
        return getattr(self.dut, f"{self.prefix}{name}")

    async def write(self, addr, data, strb=0xF):
        self._sig("awvalid").value = 1
        self._sig("awaddr").value = addr
        self._sig("wvalid").value = 1
        self._sig("wdata").value = data
        self._sig("wstrb").value = strb
        self._sig("bready").value = 1

        while True:
            await RisingEdge(self.clk)
            if int(self._sig("awready").value) and int(self._sig("wready").value):
                break
        self._sig("awvalid").value = 0
        self._sig("wvalid").value = 0

        while int(self._sig("bvalid").value) != 1:
            await RisingEdge(self.clk)
        self._sig("bready").value = 0
        await RisingEdge(self.clk)

    async def read(self, addr):
        self._sig("arvalid").value = 1
        self._sig("araddr").value = addr
        self._sig("rready").value = 1

        while True:
            await RisingEdge(self.clk)
            if int(self._sig("arready").value):
                break
        self._sig("arvalid").value = 0

        while int(self._sig("rvalid").value) != 1:
            await RisingEdge(self.clk)
        data = int(self._sig("rdata").value)
        self._sig("rready").value = 0
        await RisingEdge(self.clk)
        return data
