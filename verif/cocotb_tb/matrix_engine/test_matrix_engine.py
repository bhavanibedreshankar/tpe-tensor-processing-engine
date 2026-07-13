"""
Matrix Compute Engine testbench. Loads A/B/C_in tiles through the four
dp_ram-style buffer ports (reusing verif/cocotb_tb/env/SyncPortAgent from
M1), drives the start/dim_m/dim_k/dim_n control signals directly (this
standalone control interface is superseded by the real Command Processor
register interface in M4 -- see docs/architecture/tpe_architecture_spec.md),
waits for done, reads the result tile back, and checks it against the C++
golden model (model/build/tpe_model matmul).

DUT is instantiated at a small ROWS=COLS=4 array size (see Makefile) for
fast simulation -- the architecture explicitly scales the same interface up
to 16x16/32x32/64x64, so testing the systolic timing logic at 4x4 exercises
the same paths correctly while keeping debug tractable.
"""
import random
import struct
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from pyuvm import ConfigDB

from verif.cocotb_tb.env.golden_model import run_tpe_model
from verif.cocotb_tb.env.tpe_base_test import TpeBaseTest
from verif.cocotb_tb.matrix_engine.env import MatrixEngineEnv
from verif.cocotb_tb.matrix_engine.sequences import (
    load_act_tile,
    load_seed_tile,
    load_weight_tile,
    read_out_tile,
)

ROWS = 4
COLS = 4


async def run_matmul(dut, env, m, k, n, a_rows, b_rows, c_in_rows, label):
    await load_weight_tile(env.agent_weight.sequencer, b_rows, COLS)
    await load_act_tile(env.agent_act.sequencer, a_rows, ROWS)
    await load_seed_tile(env.agent_seed.sequencer, c_in_rows, COLS)

    dut.dim_m.value = m
    dut.dim_k.value = k
    dut.dim_n.value = n
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    cycles = 0
    while int(dut.done.value) != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < 2000, f"[{label}] engine never asserted done"

    overflow_sticky = bool(int(dut.overflow_sticky.value))

    rtl_out = await read_out_tile(env.agent_out, env.out_collector, m, COLS)
    rtl_out_active = [row[:n] for row in rtl_out]
    # a_rows/b_rows may be padded to the full ROWS/COLS width for hardware
    # loading (see load_act_tile/load_weight_tile) -- only the first k/n
    # columns are the real tile.
    a_rows_active = [row[:k] for row in a_rows]
    b_rows_active = [row[:n] for row in b_rows]
    c_in_rows_active = [row[:n] for row in c_in_rows]
    golden_overflow = env.scoreboard.check(
        a_rows_active, b_rows_active, c_in_rows_active, rtl_out_active, label=label
    )
    assert overflow_sticky == golden_overflow, (
        f"[{label}] overflow_sticky={overflow_sticky} but golden overflow={golden_overflow}"
    )
    await RisingEdge(dut.clk)


def _zero_rows(rows, cols):
    return [[0] * cols for _ in range(rows)]


class MatrixEngineTestBase(TpeBaseTest):
    def build_phase(self):
        ConfigDB().set(None, "*", "DUT", cocotb.top)
        self.env = MatrixEngineEnv("env", self)


class MatmulSanityTest(MatrixEngineTestBase):
    async def run_test_body(self):
        # 3x4x4 GEMM using the full array (k=ROWS, n=COLS), fresh (zero)
        # C_in. Hand-checkable by inspection.
        m, k, n = 3, ROWS, COLS
        a_rows = [[1, 2, 3, 4], [5, 6, 7, 8], [-1, -2, -3, -4]]
        b_rows = [[1, 0, 1, 1], [0, 1, 1, 0], [1, 1, 0, 1], [2, 0, 0, 1]]
        c_in_rows = _zero_rows(m, COLS)
        await run_matmul(cocotb.top, self.env, m, k, n, a_rows, b_rows, c_in_rows, "sanity")


class MatmulRandomTest(MatrixEngineTestBase):
    async def run_test_body(self):
        from tools.common.seed import get_seed
        rng = random.Random(get_seed(7))
        for i in range(10):
            m = rng.randint(1, 8)
            k = rng.randint(1, ROWS)
            n = rng.randint(1, COLS)
            # Keep magnitudes small enough that legitimate GEMM values stay
            # well inside int32 -- overflow behavior is covered by its own
            # directed test, not fuzzed here.
            a_rows = [[rng.randint(-8, 8) for _ in range(ROWS)] for _ in range(m)]
            b_rows = [[rng.randint(-8, 8) for _ in range(COLS)] for _ in range(k)]
            c_in_rows = [[rng.randint(-100, 100) for _ in range(COLS)] for _ in range(m)]
            await run_matmul(cocotb.top, self.env, m, k, n, a_rows, b_rows, c_in_rows, f"random{i}")


def _pad(rows, width):
    return [row + [0] * (width - len(row)) for row in rows]


class MatmulOverflowTest(MatrixEngineTestBase):
    async def run_test_body(self):
        # Force a positive-saturation and a negative-saturation case.
        # b_rows/c_in_rows are padded to COLS/ COLS width since the buffer
        # words are always full-width -- only column 0 (n=1) is real.
        m, k, n = 1, ROWS, 1
        a_rows = [[127, 127, 127, 127]]
        b_rows = _pad([[127], [127], [127], [127]], COLS)
        c_in_rows = _pad([[2147483647 - 1000]], COLS)
        await run_matmul(cocotb.top, self.env, m, k, n, a_rows, b_rows, c_in_rows, "overflow_pos")

        a_rows = [[127, 127, 127, 127]]
        b_rows = _pad([[-128], [-128], [-128], [-128]], COLS)
        c_in_rows = _pad([[-2147483647 - 1 + 1000]], COLS)
        await run_matmul(cocotb.top, self.env, m, k, n, a_rows, b_rows, c_in_rows, "overflow_neg")


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # See verif/cocotb_tb/sram/README.md for why this settle is needed:
    # cocotb's Clock produces its first RisingEdge at t=0, which can race a
    # SyncPortDriver's very first item ahead of the monitor's first sample.
    for _ in range(2):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _run(test_name, dut):
    await _start_clock(dut)
    import pyuvm
    await pyuvm.uvm_root().run_test(test_name)


@cocotb.test()
async def matmul_sanity_test(dut):
    await _run("MatmulSanityTest", dut)


@cocotb.test()
async def matmul_random_test(dut):
    await _run("MatmulRandomTest", dut)


@cocotb.test()
async def matmul_overflow_test(dut):
    await _run("MatmulOverflowTest", dut)


@cocotb.test()
async def matmul_cmodel_integration_test(dut):
    """Deliberately malformed matmul invocation (bug #10, see
    docs/verification/bug_list.md): a testbench/golden-model config-drift
    bug, not an RTL defect -- the stimulus header claims N=3 but only 2
    columns of B/C_in data are actually supplied, so tpe_model's own
    stimulus-file size check (main.cpp's cmd_matmul) legitimately rejects
    it, raising CModelError. Doesn't drive the DUT at all -- purely about
    the model/testbench call contract, not RTL behavior."""
    await _start_clock(dut)

    work_dir = Path("matmul_scoreboard_work")
    work_dir.mkdir(exist_ok=True)
    stim_path = work_dir / "stim_cmodel_integration.bin"
    out_path = work_dir / "out_cmodel_integration.bin"

    m, k, n_claimed, n_actual = 1, 1, 3, 2
    with open(stim_path, "wb") as f:
        f.write(struct.pack("<III", m, k, n_claimed))  # header claims N=3
        f.write(bytes([1] * (m * k)))                   # A: m*k
        f.write(bytes([1] * (k * n_actual)))             # B: only k*n_actual (2, not 3!)
        f.write(struct.pack(f"<{m * n_actual}i", *([0] * (m * n_actual))))  # C_in: m*n_actual

    run_tpe_model("matmul", str(stim_path), str(out_path))
