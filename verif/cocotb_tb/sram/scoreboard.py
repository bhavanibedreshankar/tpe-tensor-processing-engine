"""
SRAM scoreboard: two independent checks against one shared Python shadow
memory (itself acting as a lightweight golden model), plus a final
whole-image cross-check against the real C++ golden model
(model/build/tpe_model, see ../env/golden_model.py) to prove out the
file-based golden-model integration pattern before M2 needs it for real
compute.

Live check (per port, per cycle): SyncPortMonitor already aligns each txn's
ctrl fields and rdata to the same operation (see its docstring), so this
just predicts txn.rdata from shadow[txn.addr] *before* applying txn's own
write (matching dp_ram.sv's read-old-data-on-write semantics), then applies
the write. Every write updates the shared shadow so a write on one port is
visible to a read on the other port the following cycle.
"""
import struct
from pathlib import Path

import cocotb
import pyuvm
from pyuvm import uvm_scoreboard

from verif.cocotb_tb.env.golden_model import run_tpe_model
from verif.cocotb_tb.sram import coverage as sram_coverage


class SramScoreboard(uvm_scoreboard):
    def __init__(self, name, parent, depth=4096, row_bytes=16):
        super().__init__(name, parent)
        self.depth = depth
        self.row_bytes = row_bytes

    def build_phase(self):
        self.fifo_a = pyuvm.uvm_tlm_analysis_fifo("fifo_a", self)
        self.fifo_b = pyuvm.uvm_tlm_analysis_fifo("fifo_b", self)
        self.get_a = pyuvm.uvm_get_port("get_a", self)
        self.get_b = pyuvm.uvm_get_port("get_b", self)
        self.shadow = {}
        self.write_log = []
        self.errors = 0
        self.checked = 0

    def connect_phase(self):
        self.get_a.connect(self.fifo_a.get_export)
        self.get_b.connect(self.fifo_b.get_export)

    def _row(self, addr):
        return self.shadow.setdefault(addr, bytearray(self.row_bytes))

    def _row_to_int(self, row):
        return int.from_bytes(row, "little")

    def _apply_write(self, addr, strb, wdata_int):
        row = self._row(addr)
        wbytes = wdata_int.to_bytes(self.row_bytes, "little")
        for i in range(self.row_bytes):
            if strb & (1 << i):
                row[i] = wbytes[i]
        self.write_log.append((addr, strb & 0xFFFFFFFF, bytes(wbytes)))

    async def _process(self, get_port, port_name):
        sample = sram_coverage.sample_port_a if port_name == "port_a" else sram_coverage.sample_port_b
        while True:
            txn = await get_port.get()
            sample(txn)
            if txn.en:
                expected = self._row_to_int(self._row(txn.addr))
                self.checked += 1
                if txn.rdata != expected:
                    self.errors += 1
                    self.logger.error(
                        f"[{port_name}] rdata mismatch at addr={txn.addr}: "
                        f"got=0x{txn.rdata:032x} expected=0x{expected:032x}"
                    )
                if txn.we:
                    self._apply_write(txn.addr, txn.strb, txn.wdata)

    async def run_phase(self):
        cocotb.start_soon(self._process(self.get_a, "port_a"))
        cocotb.start_soon(self._process(self.get_b, "port_b"))

    def report_phase(self):
        self.logger.info(f"live check: {self.checked} reads checked, {self.errors} mismatches")
        sram_coverage.report(self.logger)
        sram_coverage.export(Path("sram_coverage.xml"))
        assert self.errors == 0, f"live scoreboard saw {self.errors} mismatches"

        if not self.write_log:
            self.logger.info("no writes observed, skipping golden-model cross-check")
            return

        work_dir = Path("sram_scoreboard_work")
        work_dir.mkdir(exist_ok=True)
        ops_path = work_dir / "ops.bin"
        image_path = work_dir / "golden_image.bin"

        with open(ops_path, "wb") as f:
            for addr, strb, wbytes in self.write_log:
                f.write(struct.pack("<II16s", addr, strb, wbytes))

        run_tpe_model("sram-apply", str(ops_path), str(image_path), str(self.depth), str(self.row_bytes))

        golden_image = image_path.read_bytes()
        mismatches = 0
        for addr in range(self.depth):
            shadow_row = bytes(self.shadow.get(addr, bytearray(self.row_bytes)))
            golden_row = golden_image[addr * self.row_bytes:(addr + 1) * self.row_bytes]
            if shadow_row != golden_row:
                mismatches += 1
                if mismatches <= 5:
                    self.logger.error(
                        f"golden-model mismatch at addr={addr}: "
                        f"shadow={shadow_row.hex()} golden={golden_row.hex()}"
                    )

        self.logger.info(
            f"golden-model cross-check: {len(self.write_log)} writes replayed, "
            f"{mismatches} row mismatches out of {self.depth}"
        )
        assert mismatches == 0, f"golden model cross-check found {mismatches} mismatches"
