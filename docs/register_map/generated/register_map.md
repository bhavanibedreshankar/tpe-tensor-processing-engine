<!--
GENERATED FILE -- DO NOT EDIT.
Source of truth: docs/register_map/tpe_regs.yaml
Regenerate with: make regmap  (or python3 tools/regmap_gen.py)
-->
# TPE Register Map

Tensor Processing Engine MMIO register space, accessed by the host over an AXI4-Lite port terminating in the Command Processor. Each block below owns a 4KB-aligned window.

Address width: 16 bits. Data width: 32 bits.


## cp (base `0x0000`)

Command Processor -- control/status and command staging.

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
| `VERSION` | `0x00` | `0x0000` | RO | `0x00010000` | {MAJOR, MINOR} version of the TPE RTL. |
| `CTRL` | `0x04` | `0x0004` | RW | `0x00000000` | Top-level enable / soft reset. |
| `STATUS` | `0x08` | `0x0008` | RO | `0x00000004` | Command Processor status. |
| `CMD_OPCODE_TAG` | `0x10` | `0x0010` | RW | `0x00000000` | Staged command opcode + caller tag (see tpe_pkg::cmd_opcode_e). |
| `CMD_SRAM_ADDR` | `0x14` | `0x0014` | RW | `0x00000000` | Staged scratchpad address operand. |
| `CMD_MEM_ADDR` | `0x18` | `0x0018` | RW | `0x00000000` | Staged DDR (AXI) address operand. |
| `CMD_DIM_MK` | `0x1c` | `0x001c` | RW | `0x00000000` | Staged tile M/K dimensions. |
| `CMD_DIM_N` | `0x20` | `0x0020` | RW | `0x00000000` | Staged tile N dimension. |
| `CMD_PUSH` | `0x24` | `0x0024` | WO | `0x00000000` | Write 1 to atomically push the staged command into the command FIFO. |
| `IRQ_STATUS` | `0x30` | `0x0030` | RW1C | `0x00000000` | Interrupt status, write-1-to-clear. |
| `IRQ_ENABLE` | `0x34` | `0x0034` | RW | `0x00000000` | Interrupt enable mask (same bit layout as IRQ_STATUS). |


**VERSION fields:**

| Field | Bits | Description |
|---|---|---|
| `MINOR` | `[15:0]` | Minor version |
| `MAJOR` | `[31:16]` | Major version |


**CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `ENABLE` | `[0:0]` | 1 = CP accepts commands |
| `SOFT_RESET` | `[1:1]` | 1 = pulse to reset CP/scheduler datapath |


**STATUS fields:**

| Field | Bits | Description |
|---|---|---|
| `BUSY` | `[0:0]` | 1 = a command is executing |
| `CMD_FIFO_FULL` | `[1:1]` |  |
| `CMD_FIFO_EMPTY` | `[2:2]` |  |
| `ERROR` | `[3:3]` | 1 = last command completed with STAT != OK |
| `LAST_STATUS` | `[6:4]` | cmd_status_e of the last completed command |


**CMD_OPCODE_TAG fields:**

| Field | Bits | Description |
|---|---|---|
| `OPCODE` | `[3:0]` |  |
| `TAG` | `[15:4]` |  |


**CMD_DIM_MK fields:**

| Field | Bits | Description |
|---|---|---|
| `DIM_M` | `[15:0]` |  |
| `DIM_K` | `[31:16]` |  |


**CMD_DIM_N fields:**

| Field | Bits | Description |
|---|---|---|
| `DIM_N` | `[15:0]` |  |


**CMD_PUSH fields:**

| Field | Bits | Description |
|---|---|---|
| `PUSH` | `[0:0]` |  |


**IRQ_STATUS fields:**

| Field | Bits | Description |
|---|---|---|
| `CMD_DONE` | `[0:0]` |  |
| `CMD_ERROR` | `[1:1]` |  |


**IRQ_ENABLE fields:**

| Field | Bits | Description |
|---|---|---|
| `CMD_DONE_EN` | `[0:0]` |  |
| `CMD_ERROR_EN` | `[1:1]` |  |



## dma (base `0x1000`)

DMA Engine -- descriptor-based DDR <-> SRAM mover.

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
| `CTRL` | `0x00` | `0x1000` | RW | `0x00000000` |  |
| `STATUS` | `0x04` | `0x1004` | RO | `0x00000001` |  |
| `DESC_MEM_ADDR` | `0x10` | `0x1010` | RW | `0x00000000` | DDR-side address for the in-flight descriptor. |
| `DESC_SRAM_ADDR` | `0x14` | `0x1014` | RW | `0x00000000` | SRAM-side address for the in-flight descriptor. |
| `DESC_LEN` | `0x18` | `0x1018` | RW | `0x00000000` | Transfer length in bytes. |
| `DESC_CTRL` | `0x1c` | `0x101c` | RW | `0x00000000` |  |


**CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `ENABLE` | `[0:0]` |  |


**STATUS fields:**

| Field | Bits | Description |
|---|---|---|
| `IDLE` | `[0:0]` |  |
| `ERROR` | `[1:1]` |  |


**DESC_CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `DIR` | `[0:0]` | 0 = DDR->SRAM, 1 = SRAM->DDR |
| `START` | `[1:1]` | write 1 to kick off the descriptor |



## matrix_engine (base `0x2000`)

Matrix Compute Engine (MAC array + accumulator) configuration.

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
| `CTRL` | `0x00` | `0x2000` | RW | `0x00000000` |  |
| `STATUS` | `0x04` | `0x2004` | RO | `0x00000001` |  |
| `DIM_MK` | `0x10` | `0x2010` | RW | `0x00000000` |  |
| `DIM_N` | `0x14` | `0x2014` | RW | `0x00000000` |  |


**CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `START` | `[0:0]` |  |


**STATUS fields:**

| Field | Bits | Description |
|---|---|---|
| `IDLE` | `[0:0]` |  |
| `OVERFLOW_STICKY` | `[1:1]` | accumulator saturated at least once |


**DIM_MK fields:**

| Field | Bits | Description |
|---|---|---|
| `DIM_M` | `[15:0]` |  |
| `DIM_K` | `[31:16]` |  |


**DIM_N fields:**

| Field | Bits | Description |
|---|---|---|
| `DIM_N` | `[15:0]` |  |



## pmu (base `0x3000`)

Performance Monitor Unit -- free-running event counters.

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
| `CTRL` | `0x00` | `0x3000` | RW | `0x00000000` |  |
| `CYCLE_COUNT` | `0x10` | `0x3010` | RO | `0x00000000` | Free-running cycle counter since last RESET_COUNTERS. |
| `MAC_ACTIVE_COUNT` | `0x14` | `0x3014` | RO | `0x00000000` | Cycles the MAC array produced a valid result. |
| `DMA_WAIT_COUNT` | `0x18` | `0x3018` | RO | `0x00000000` | Cycles the scheduler stalled waiting on DMA. |
| `SCHED_STALL_COUNT` | `0x1c` | `0x301c` | RO | `0x00000000` | Cycles the scheduler had work but could not issue. |
| `IDLE_COUNT` | `0x20` | `0x3020` | RO | `0x00000000` | Cycles with no in-flight command. |
| `CMD_LATENCY_LAST` | `0x24` | `0x3024` | RO | `0x00000000` | Cycle latency of the most recently completed command. |


**CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `ENABLE` | `[0:0]` |  |
| `RESET_COUNTERS` | `[1:1]` |  |



## debug (base `0x4000`)

Debug infrastructure -- command trace buffer and error capture.

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
| `CTRL` | `0x00` | `0x4000` | RW | `0x00000000` |  |
| `TRACE_STATUS` | `0x04` | `0x4004` | RO | `0x00000000` |  |
| `TRACE_RDATA` | `0x08` | `0x4008` | RO | `0x00000000` | Pop the oldest trace entry. A read at this address dequeues the trace FIFO; the popped opcode/tag/status is returned in this same transaction's read data. |
| `ERROR_CODE` | `0x10` | `0x4010` | RO | `0x00000000` | cmd_status_e of the most recent error. |
| `ERROR_TAG` | `0x14` | `0x4014` | RO | `0x00000000` | Command tag associated with ERROR_CODE. |


**CTRL fields:**

| Field | Bits | Description |
|---|---|---|
| `TRACE_ENABLE` | `[0:0]` |  |


**TRACE_STATUS fields:**

| Field | Bits | Description |
|---|---|---|
| `TRACE_EMPTY` | `[0:0]` |  |
| `TRACE_FULL` | `[1:1]` |  |
| `TRACE_COUNT` | `[12:2]` |  |


**TRACE_RDATA fields:**

| Field | Bits | Description |
|---|---|---|
| `OPCODE` | `[3:0]` | cmd_opcode_e of the completed command |
| `TAG` | `[15:4]` | caller tag of the completed command |
| `STATUS` | `[18:16]` | cmd_status_e of the completed command |



