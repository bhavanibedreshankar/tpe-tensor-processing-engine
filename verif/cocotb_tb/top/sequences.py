"""AXI4-Lite command-staging helpers for the top-level testbench, driving
verif/cocotb_tb/env/axi4_lite_driver.Axi4LiteDriver against the generated
register addresses (verif/cocotb_tb/env/tpe_regs.py)."""
from cocotb.triggers import RisingEdge

from verif.cocotb_tb.env import tpe_regs as regs


async def enable_cp(axi):
    await axi.write(regs.CP_CTRL_ADDR, 1 << regs.CP_CTRL_ENABLE_LSB)


async def push_command(axi, opcode, tag, sram_addr, mem_addr, dim_m, dim_k, dim_n):
    opcode_tag = (opcode & 0xF) | ((tag & 0xFFF) << 4)
    await axi.write(regs.CP_CMD_OPCODE_TAG_ADDR, opcode_tag)
    await axi.write(regs.CP_CMD_SRAM_ADDR_ADDR, sram_addr)
    await axi.write(regs.CP_CMD_MEM_ADDR_ADDR, mem_addr)
    dim_mk = (dim_m & 0xFFFF) | ((dim_k & 0xFFFF) << 16)
    await axi.write(regs.CP_CMD_DIM_MK_ADDR, dim_mk)
    await axi.write(regs.CP_CMD_DIM_N_ADDR, dim_n & 0xFFFF)
    await axi.write(regs.CP_CMD_PUSH_ADDR, 1 << regs.CP_CMD_PUSH_PUSH_LSB)


async def wait_idle(dut, axi, clk, timeout_cycles=5000):
    cycles = 0
    while True:
        status = await axi.read(regs.CP_STATUS_ADDR)
        busy = (status >> regs.CP_STATUS_BUSY_LSB) & 1
        if not busy:
            return status
        await RisingEdge(clk)
        cycles += 1
        assert cycles < timeout_cycles, "timed out waiting for CP_STATUS.BUSY to clear"


def status_last_status(status_word):
    return (status_word >> regs.CP_STATUS_LAST_STATUS_LSB) & 0x7


def status_error(status_word):
    return (status_word >> regs.CP_STATUS_ERROR_LSB) & 1


async def run_command(dut, axi, clk, opcode, tag, sram_addr=0, mem_addr=0, dim_m=0, dim_k=0, dim_n=0):
    await push_command(axi, opcode, tag, sram_addr, mem_addr, dim_m, dim_k, dim_n)
    status = await wait_idle(dut, axi, clk)
    return status
