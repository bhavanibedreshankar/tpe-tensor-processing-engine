"""
DMA scoreboard: maintains Python-side shadow images of DDR and SRAM,
mirroring exactly what the test has preloaded via backdoor writes. Each
DMA operation is replayed through the C++ golden model
(model/build/tpe_model dma-apply) against the *current* shadow, which then
becomes the new shadow baseline (so chained/back-to-back DMA tests compose
correctly without needing a fresh full-image readback each time). Only the
rows actually touched by an operation are read back from the RTL via
backdoor and diffed against the shadow -- exhaustive full-memory sweeps
aren't needed since dp_ram's own correctness is already covered by M1's
SRAM tests; this scoreboard is about the DMA's addressing/sequencing.
"""
import struct
from pathlib import Path

from pyuvm import uvm_scoreboard

from verif.cocotb_tb.env.errors import MismatchError
from verif.cocotb_tb.env.golden_model import run_tpe_model


class DmaScoreboard(uvm_scoreboard):
    def __init__(self, name, parent, ddr_depth, sram_depth, row_bytes=16):
        super().__init__(name, parent)
        self.ddr_depth = ddr_depth
        self.sram_depth = sram_depth
        self.row_bytes = row_bytes

    def build_phase(self):
        self.ddr_shadow = bytearray(self.ddr_depth * self.row_bytes)
        self.sram_shadow = bytearray(self.sram_depth * self.row_bytes)
        self.checked = 0
        self.mismatches = 0

    def _put(self, shadow, row, value_int):
        off = row * self.row_bytes
        shadow[off:off + self.row_bytes] = value_int.to_bytes(self.row_bytes, "little")

    def record_ddr_write(self, row, value_int):
        self._put(self.ddr_shadow, row, value_int)

    def record_sram_write(self, row, value_int):
        self._put(self.sram_shadow, row, value_int)

    def apply_dma(self, mem_row, sram_row, n_rows, dir_sram_to_ddr, label):
        """Runs the golden model on the current shadow images and replaces
        the shadow with the golden 'after' state."""
        work_dir = Path("dma_scoreboard_work")
        work_dir.mkdir(exist_ok=True)
        stim_path = work_dir / f"stim_{label}.bin"
        out_path = work_dir / f"out_{label}.bin"

        with open(stim_path, "wb") as f:
            f.write(struct.pack("<IIII", mem_row, sram_row, n_rows, 1 if dir_sram_to_ddr else 0))
            f.write(bytes(self.ddr_shadow))
            f.write(bytes(self.sram_shadow))

        run_tpe_model(
            "dma-apply", str(stim_path), str(out_path), str(self.ddr_depth), str(self.sram_depth), str(self.row_bytes)
        )

        raw = out_path.read_bytes()
        ddr_bytes = self.ddr_depth * self.row_bytes
        sram_bytes = self.sram_depth * self.row_bytes
        assert len(raw) == ddr_bytes + sram_bytes, f"dma-apply output size mismatch: {len(raw)}"
        self.ddr_shadow = bytearray(raw[:ddr_bytes])
        self.sram_shadow = bytearray(raw[ddr_bytes:ddr_bytes + sram_bytes])

    def expected_row(self, kind, row):
        shadow = self.ddr_shadow if kind == "ddr" else self.sram_shadow
        off = row * self.row_bytes
        return int.from_bytes(shadow[off:off + self.row_bytes], "little")

    def check_row(self, kind, row, rtl_value_int, label=""):
        expected = self.expected_row(kind, row)
        self.checked += 1
        if expected != rtl_value_int:
            self.mismatches += 1
            self.logger.error(
                f"[{label}] {kind} row {row} mismatch: "
                f"rtl=0x{rtl_value_int:032x} expected=0x{expected:032x}"
            )

    def report_phase(self):
        self.logger.info(f"dma scoreboard: {self.checked} rows checked, {self.mismatches} mismatches")
        if self.mismatches:
            raise MismatchError(f"{self.mismatches} row mismatches")
