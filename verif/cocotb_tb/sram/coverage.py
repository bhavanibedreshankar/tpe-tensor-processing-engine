"""
TB-side stimulus/scenario coverage via cocotb-coverage, complementing the
RTL-side hardware-state covergroups in verif/coverage/sram_cov.sv (see
docs/verification/coverage_plan.md section 1 for the split rationale).
"""
from cocotb_coverage.coverage import CoverCross, CoverPoint, coverage_db

SRAM_DEPTH = 4096


def _op_type(txn):
    if not txn.en:
        return "idle"
    return "write" if txn.we else "read"


def _addr_region(txn):
    third = SRAM_DEPTH // 3
    if txn.addr <= third:
        return "low"
    if txn.addr <= 2 * third:
        return "mid"
    return "high"


@CoverPoint("sram.port_a.op_type", xf=_op_type, bins=["read", "write", "idle"])
@CoverPoint("sram.port_a.addr_region", xf=_addr_region, bins=["low", "mid", "high"])
def sample_port_a(txn):
    pass


@CoverPoint("sram.port_b.op_type", xf=_op_type, bins=["read", "write", "idle"])
@CoverPoint("sram.port_b.addr_region", xf=_addr_region, bins=["low", "mid", "high"])
def sample_port_b(txn):
    pass


CoverCross("sram.port_a.op_x_region", items=["sram.port_a.op_type", "sram.port_a.addr_region"])
CoverCross("sram.port_b.op_x_region", items=["sram.port_b.op_type", "sram.port_b.addr_region"])


def report(logger):
    coverage_db.report_coverage(logger.info, bins=False)


def export(path):
    coverage_db.export_to_xml(filename=str(path))
