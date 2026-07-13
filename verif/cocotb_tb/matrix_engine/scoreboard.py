"""
Matrix Compute Engine scoreboard: unlike SRAM's live per-cycle check, this
compares the RTL's *final* output tile against the C++ golden model
(model/build/tpe_model matmul), matching the architecture decision that a
parallel Python reimplementation of the compute math isn't the point here
-- the C++ model IS the spec. The test drives A/B/C_in directly (see
sequences.py) and hands them to check() together with the RTL-observed
output tile once the engine reports done.
"""
import struct
from pathlib import Path

from pyuvm import uvm_scoreboard

from verif.cocotb_tb.env.errors import MismatchError
from verif.cocotb_tb.env.golden_model import run_tpe_model


class MatmulScoreboard(uvm_scoreboard):
    def build_phase(self):
        self.checked = 0
        self.mismatches = 0

    def check(self, a_rows, b_rows, c_in_rows, rtl_out_rows, label=""):
        """a_rows: MxK list-of-lists (int8), b_rows: KxN, c_in_rows: MxN
        (int32), rtl_out_rows: MxN (int32, from the RTL's output buffer).
        Raises AssertionError on any mismatch."""
        m = len(a_rows)
        k = len(a_rows[0]) if m else 0
        n = len(b_rows[0]) if b_rows else 0
        assert len(b_rows) == k
        assert len(c_in_rows) == m and (m == 0 or len(c_in_rows[0]) == n)
        assert len(rtl_out_rows) == m and (m == 0 or len(rtl_out_rows[0]) == n)

        work_dir = Path("matmul_scoreboard_work")
        work_dir.mkdir(exist_ok=True)
        stim_path = work_dir / f"stim_{label}.bin"
        out_path = work_dir / f"out_{label}.bin"

        with open(stim_path, "wb") as f:
            f.write(struct.pack("<III", m, k, n))
            for row in a_rows:
                f.write(bytes(v & 0xFF for v in row))
            for row in b_rows:
                f.write(bytes(v & 0xFF for v in row))
            for row in c_in_rows:
                for v in row:
                    f.write(struct.pack("<i", v))

        run_tpe_model("matmul", str(stim_path), str(out_path))

        raw = out_path.read_bytes()
        c_bytes = m * n * 4
        golden_flat = struct.unpack(f"<{m * n}i", raw[:c_bytes])
        (golden_overflow,) = struct.unpack("<I", raw[c_bytes:c_bytes + 4])

        self.checked += 1
        mismatches_here = 0
        for mi in range(m):
            for ni in range(n):
                golden_v = golden_flat[mi * n + ni]
                rtl_v = rtl_out_rows[mi][ni]
                if golden_v != rtl_v:
                    mismatches_here += 1
                    self.logger.error(
                        f"[{label}] mismatch at ({mi},{ni}): rtl=0x{rtl_v & 0xFFFFFFFF:08x} "
                        f"golden=0x{golden_v & 0xFFFFFFFF:08x}"
                    )
        if mismatches_here:
            self.mismatches += 1
        self.logger.info(
            f"[{label}] {m}x{k}x{n}: {m * n - mismatches_here}/{m * n} values matched, "
            f"golden_overflow={bool(golden_overflow)}"
        )
        if mismatches_here:
            raise MismatchError(f"[{label}] {mismatches_here} value mismatches")
        return bool(golden_overflow)

    def report_phase(self):
        self.logger.info(f"matmul scoreboard: {self.checked} checks run, {self.mismatches} had mismatches")
        if self.mismatches:
            raise MismatchError(f"{self.mismatches} check(s) had mismatches")
