"""
Top-level (end-to-end) scoreboard. Reuses the *same* C++ golden model as
M2's matrix_engine scoreboard (model/build/tpe_model matmul) to predict the
GEMM result, then packs that result into the exact byte layout
rtl/top/tpe_top.sv's output chunk-adapter produces in DDR (see that file's
header comment: out_buf's row is ObufChunksPerRow x wider than one AXI
beat, so a STORE writes ObufChunksPerRow 128-bit chunks per M-row). This is
deliberately *not* re-implemented in C++: it's a byte-layout detail of this
repo's V1 top-level integration, not part of the matmul math the golden
model owns.
"""
import struct
from pathlib import Path

from pyuvm import uvm_scoreboard

from verif.cocotb_tb.env.golden_model import run_tpe_model

COLS = 16
ACCUM_WIDTH = 32
AXI_DATA_WIDTH = 128
CHUNKS_PER_ROW = (COLS * ACCUM_WIDTH) // AXI_DATA_WIDTH  # 4
COLS_PER_CHUNK = AXI_DATA_WIDTH // ACCUM_WIDTH  # 4


class TopScoreboard(uvm_scoreboard):
    def __init__(self, name, parent, ddr_depth):
        super().__init__(name, parent)
        self.ddr_depth = ddr_depth

    def build_phase(self):
        self.checked = 0
        self.mismatches = 0

    def golden_matmul(self, a_rows, b_rows, dim_m, dim_k, dim_n, label):
        """a_rows: dim_m x dim_k int8, b_rows: dim_k x dim_n int8. Returns
        the dim_m x dim_n int32 result via the C++ golden model."""
        work_dir = Path("top_scoreboard_work")
        work_dir.mkdir(exist_ok=True)
        stim_path = work_dir / f"stim_{label}.bin"
        out_path = work_dir / f"out_{label}.bin"

        c_in_rows = [[0] * dim_n for _ in range(dim_m)]
        with open(stim_path, "wb") as f:
            f.write(struct.pack("<III", dim_m, dim_k, dim_n))
            for row in a_rows:
                f.write(bytes(v & 0xFF for v in row))
            for row in b_rows:
                f.write(bytes(v & 0xFF for v in row))
            for row in c_in_rows:
                for v in row:
                    f.write(struct.pack("<i", v))

        run_tpe_model("matmul", str(stim_path), str(out_path))

        raw = out_path.read_bytes()
        c_bytes = dim_m * dim_n * 4
        flat = struct.unpack(f"<{dim_m * dim_n}i", raw[:c_bytes])
        return [[flat[m * dim_n + n] for n in range(dim_n)] for m in range(dim_m)]

    def expected_store_rows(self, c_matrix, dim_m, dim_n):
        """Packs c_matrix into the chunk-interleaved 128-bit words tpe_top's
        STORE path writes to DDR, in order."""
        words = []
        for m in range(dim_m):
            for chunk in range(CHUNKS_PER_ROW):
                word = 0
                for i in range(COLS_PER_CHUNK):
                    col = chunk * COLS_PER_CHUNK + i
                    val = c_matrix[m][col] if col < dim_n else 0
                    word |= (val & 0xFFFFFFFF) << (i * 32)
                words.append(word)
        return words

    def check_store(self, expected_words, rtl_words, label=""):
        self.checked += 1
        mismatches_here = 0
        for i, (exp, got) in enumerate(zip(expected_words, rtl_words)):
            if exp != got:
                mismatches_here += 1
                self.logger.error(f"[{label}] store word {i} mismatch: rtl=0x{got:032x} expected=0x{exp:032x}")
        if mismatches_here:
            self.mismatches += 1
        self.logger.info(
            f"[{label}] store check: {len(expected_words) - mismatches_here}/{len(expected_words)} words matched"
        )
        assert mismatches_here == 0, f"[{label}] {mismatches_here} store word mismatches"

    def report_phase(self):
        self.logger.info(f"top scoreboard: {self.checked} checks run, {self.mismatches} had mismatches")
        assert self.mismatches == 0, f"{self.mismatches} check(s) had mismatches"
