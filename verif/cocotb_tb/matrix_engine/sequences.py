"""
Buffer load/readback helpers for the Matrix Compute Engine testbench.
Each of the four buffers (weight/act/seed/out) is a plain
rtl/common/dp_ram.sv instance whose port A follows the same convention
verif/cocotb_tb/env/SyncPortAgent already knows how to drive -- these
functions just pack/unpack the wide per-row words dp_ram uses and issue
SyncPortItems through a given agent's sequencer.
"""
from pyuvm import uvm_sequence

from verif.cocotb_tb.env.sync_port_item import SyncPortItem


def _pack_row(values, field_width, n_fields):
    word = 0
    mask = (1 << field_width) - 1
    for i in range(n_fields):
        word |= (values[i] & mask) << (i * field_width)
    return word


def _unpack_row(word, field_width, n_fields, signed):
    mask = (1 << field_width) - 1
    out = []
    for i in range(n_fields):
        v = (word >> (i * field_width)) & mask
        if signed and (v & (1 << (field_width - 1))):
            v -= 1 << field_width
        out.append(v)
    return out


class _WriteRowsSeq(uvm_sequence):
    def __init__(self, name, rows, field_width, n_fields):
        super().__init__(name)
        self.rows = rows
        self.field_width = field_width
        self.n_fields = n_fields

    async def body(self):
        # dp_ram's strobe is one bit per *byte*, not per field -- for
        # 32-bit fields (the seed/out buffers) that's 4 strobe bits/field.
        field_bytes = self.field_width // 8
        strb_all = (1 << (self.n_fields * field_bytes)) - 1
        for addr, row in enumerate(self.rows):
            wdata = _pack_row(row, self.field_width, self.n_fields)
            item = SyncPortItem(en=1, we=1, strb=strb_all, addr=addr, wdata=wdata)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)


class _ReadRowsSeq(uvm_sequence):
    def __init__(self, name, n_rows):
        super().__init__(name)
        self.n_rows = n_rows

    async def body(self):
        for addr in range(self.n_rows):
            item = SyncPortItem(en=1, we=0, strb=0, addr=addr, wdata=0)
            await self.start_item(item)
            await self.finish_item(item)
        idle = SyncPortItem(en=0)
        await self.start_item(idle)
        await self.finish_item(idle)


async def load_weight_tile(sequencer, b_rows, cols):
    """b_rows: KxN int8 (row k = B[k][0:N-1])."""
    await _WriteRowsSeq("load_weight", b_rows, field_width=8, n_fields=cols).start(sequencer)


async def load_act_tile(sequencer, a_rows, rows_dim):
    """a_rows: MxK int8 (row m = A[m][0:K-1]), padded/sized to `rows_dim` fields."""
    await _WriteRowsSeq("load_act", a_rows, field_width=8, n_fields=rows_dim).start(sequencer)


async def load_seed_tile(sequencer, c_in_rows, cols):
    """c_in_rows: MxN int32."""
    await _WriteRowsSeq("load_seed", c_in_rows, field_width=32, n_fields=cols).start(sequencer)


async def read_out_tile(agent, collector, m_rows, cols):
    """Reads m_rows rows of `cols` int32 values back from the output buffer.
    `collector` is env.out_collector (a persistent OutputCollector already
    connected to agent.monitor.ap in MatrixEngineEnv.connect_phase)."""
    collector.clear()
    await _ReadRowsSeq("read_out", m_rows).start(agent.sequencer)

    result = []
    for m in range(m_rows):
        assert m in collector.collected, f"no read observed for output row {m}"
        result.append(_unpack_row(collector.collected[m], field_width=32, n_fields=cols, signed=True))
    return result
