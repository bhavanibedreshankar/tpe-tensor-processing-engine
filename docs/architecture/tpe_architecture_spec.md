# Tensor Processing Engine (TPE) -- Architecture Specification

Status: **V1 complete** (see [Roadmap](#roadmap) and the top-level
[README](../../README.md#status) for milestone tracking; V2+ scope
boundaries below).

This document is the RTL-facing architecture spec. For the original product
vision see [`overview`](../../overview) at the repo root; this doc pins down
the concrete parameters, interfaces, and block responsibilities that the RTL
in `rtl/` actually implements.

## 1. System overview

The TPE is a memory-mapped coprocessor. A host writes commands to an
AXI4-Lite register window; the Command Processor decodes and queues them;
the Scheduler dispatches DMA and Matrix Engine work, overlapping data
movement with compute; results land back in DDR via DMA; completion raises
an interrupt.

```
Host --AXI4-Lite MMIO--> Command Processor --> Scheduler --+--> DMA Engine ---AXI4---> DDR
                              ^                             |         |
                              |                             |         v
                          Debug/PMU <--------events----------+   Local SRAM (scratchpad)
                                                              |         ^
                                                              v         |
                                                        Matrix Compute Engine
                                                     (MAC array + accumulator)
```

## 2. Numeric format (V1)

| Parameter | Value | Rationale |
|---|---|---|
| Operand width | `OPERAND_WIDTH` = 8 (signed int8) | Standard quantized-inference weight/activation format |
| Accumulator width | `ACCUM_WIDTH` = 32 (signed int32) | Headroom for K-deep (up to `MAX_TILE_DIM`=256) dot products without overflow before intentional saturation |

All parameters live in `rtl/include/tpe_pkg.sv`.

## 3. Blocks

### 3.1 Command Processor (`rtl/command_processor/`)
Front door of the accelerator. Exposes the `cp` register block (see
[register map](../register_map/generated/register_map.md)) over AXI4-Lite.
Software stages a command's opcode/tag/addresses/dims into
`CMD_OPCODE_TAG`/`CMD_SRAM_ADDR`/`CMD_MEM_ADDR`/`CMD_DIM_MK`/`CMD_DIM_N`,
then writes `CMD_PUSH` to atomically enqueue a `tpe_pkg::tpe_command_t` into
the command FIFO. Validates opcode/dimensions, raises `CMD_ERROR` on bad
input, raises `CMD_DONE` on completion (see `IRQ_STATUS`/`IRQ_ENABLE`).

### 3.2 Instruction Scheduler (`rtl/scheduler/`)
Pulls commands off the command FIFO and dispatches each to the DMA Engine
or Matrix Engine. **As implemented in V1, this is a sequential dispatcher**:
one command runs to completion before the next is popped -- no overlap
between DMA prefetch and compute. The original vision of arbitrating so the
two *can* overlap (prefetching tile N+1's weights while tile N computes) is
explicitly a V2 "improved scheduler" item (see `tpe_scheduler.sv`'s header
comment and the roadmap below), consistent with the vision doc's own
phasing.

### 3.3 DMA Engine (`rtl/dma/`)
Descriptor-based mover between DDR (AXI4 master) and the Local SRAM
scratchpad. V1 scope: single channel, one descriptor in flight at a time
(`DESC_MEM_ADDR`/`DESC_SRAM_ADDR`/`DESC_LEN`/`DESC_CTRL`). Double buffering
and scatter-gather are called out as V2+ in the original vision doc and are
out of scope here.

### 3.4 Local SRAM / Scratchpad (`rtl/sram/`)
Dual-port, byte-addressable-via-strobe scratchpad (`SRAM_DEPTH` x
`SRAM_DATA_WIDTH` = 4096 x 128b = 64KB). Designed for one port to serve DMA
fill/drain and the other the Matrix Engine's input/output buffers, and
fully verified standalone as such (M1). **Not instantiated in the V1 top
level** (`rtl/top/tpe_top.sv`): V1's matmul-only command flow addresses
Matrix Engine's four internal buffers (weight/activation/seed/output)
directly as the "Local SRAM" region, routed to by the Scheduler per
command (see `tpe_top.sv`'s header comment for the full reasoning). This
block remains available for a V2+ multi-engine/multi-channel scheduler to
wire in as an actual shared scratchpad between multiple consumers.

### 3.5 Matrix Compute Engine (`rtl/matrix_engine/`)
Weight-stationary systolic array, default `MAC_ARRAY_ROWS` x
`MAC_ARRAY_COLS` = 16x16 = 256 MACs, computing `C = A x B + C` over tiles up
to `MAX_TILE_DIM` in each of M/K/N. Internally: input buffers -> MAC array
(`rtl/matrix_engine/pe.sv` x N instances) -> accumulator
(`rtl/matrix_engine/accumulator.sv`, int32, saturating) -> output buffer.

### 3.6 Performance Monitor Unit (`rtl/pmu/`)
Free-running counters exposed via the `pmu` register block: cycle count,
MAC-active cycles, DMA-wait cycles, scheduler-stall cycles, idle cycles, and
last-command latency. Counters reset via `PMU_CTRL.RESET_COUNTERS` (level-
sensitive -- counters stay pinned at 0 for as long as it's held) and gated
via `PMU_CTRL.ENABLE`. The event inputs (`mac_active`/`dma_wait`/
`sched_stall`/`sched_idle`/`dispatch_start`/`cmd_done_valid`) are an
integration-level view sourced from `tpe_scheduler.sv` (plus `me_busy`
directly for `mac_active`) -- see `tpe_scheduler.sv`'s "PMU instrumentation"
section for exact per-signal semantics (dispatch-active span, stall vs.
idle classification). `tpe_pmu.sv` is its own independent AXI4-Lite slave,
same flat-port pattern as `tpe_cmd_proc.sv`; see section 4 for how the host
reaches it.

### 3.7 Debug Infrastructure (`rtl/debug/`)
Command trace buffer (opcode/tag/status per completed command, popped via
`DEBUG_TRACE_RDATA`) plus latched error code/tag for the most recent error
(`DEBUG_ERROR_CODE`/`DEBUG_ERROR_TAG`, latched independently of tracing --
they still update even with `DEBUG_CTRL.TRACE_ENABLE=0`). Assertion status
is observed through the simulator's assertion log, not modeled as a
register (see the [verification test plan](../verification/test_plan.md)).
Also its own independent AXI4-Lite slave; its `TRACE_RDATA` register is the
only *popping* read in this repo's register map, which needs one extra
FSM state versus every other read here (see `tpe_debug.sv`'s header
comment).

## 4. Interfaces

- **Host MMIO**: AXI4-Lite, `AXIL_ADDR_WIDTH`=16, `AXIL_DATA_WIDTH`=32, on
  `tpe_top.sv`'s `s_*` ports. `tpe_top.sv` decodes the live AWADDR/ARADDR's
  block bits and routes to whichever of `tpe_cmd_proc.sv` (`cp`, base
  `0x0000`), `tpe_pmu.sv` (`pmu`, base `0x3000`), or `tpe_debug.sv`
  (`debug`, base `0x4000`) the address falls in -- `dma`/`matrix_engine`
  have no V1 AXI4-Lite window (the Scheduler drives those directly, see
  section 3.1's implementation note), and any other address falls to a
  default sink so the bus can't hang. Each of the three real slaves shares
  the same V1 simplification: AWVALID and WVALID must be presented
  together (one outstanding transaction, no independent AW/W channel
  timing) -- see `tpe_cmd_proc.sv`'s header comment. The router itself is a
  further V1 simplification: address decode is purely combinational off
  the live AWADDR/ARADDR, safe only because every V1 AXI4-Lite
  master/slave here holds the address stable from request through
  response (see `tpe_top.sv`'s header comment) -- a full crossbar with
  per-transaction address latching is out of scope. As flat port lists
  rather than a SystemVerilog `interface` construct throughout this repo
  (avoids cocotb/Verilator VPI access friction with `interface`-typed
  ports, which the M0-M5 pattern of plain ports never ran into).
- **DDR memory**: AXI4, `AXI_ADDR_WIDTH`=32, `AXI_DATA_WIDTH`=128,
  `AXI_ID_WIDTH`=4, INCR-burst-capable (`AXI_LEN_WIDTH`=8, capped at
  `MAX_BURST_BEATS`=16 beats/burst in `tpe_dma.sv`), on `tpe_top.sv`'s
  `m_*` ports. In simulation this connects to the behavioral
  `verif/models/axi4_ddr_model.sv`; on real silicon it would connect to an
  actual DDR controller.
- **Interrupt**: single-bit level interrupt, asserted while any enabled bit
  in `IRQ_STATUS` is set, cleared by writing 1 to that bit.

## 5. Software flow (matches the vision doc's example)

```
1. Host DMA's weights:  stage CMD_LOAD_WEIGHT + addrs -> CMD_PUSH
2. Host DMA's activations: stage CMD_LOAD_ACT + addrs -> CMD_PUSH
3. Host issues matmul:  stage CMD_MATMUL + dims -> CMD_PUSH
4. Host stores result:  stage CMD_STORE + addrs -> CMD_PUSH
5. Host waits for CMD_DONE interrupt (or polls CP_STATUS.BUSY)
```

Implemented and verified end-to-end in M4 -- see
`verif/cocotb_tb/top/test_top.py`'s `matmul_flow_test`, driven entirely
over the real AXI4-Lite MMIO interface (no backdoor RTL access except to
the external DDR model).

Activation functions (ReLU/GELU), quantization, multi-channel DMA, and
attention-specific ops are explicitly **V2/V3** per the roadmap below and are
not implemented in this repository yet.

## 6. Roadmap

Reproduced from the vision doc for quick reference; this repo currently
targets **Version 1** only.

- **V1** (this repo): single Matrix Engine, DMA, Local SRAM, Command
  Processor, PMU, complete verification framework.
- **V2**: activation unit (ReLU, GELU), quantization support, multiple DMA
  channels, improved scheduler.
- **V3**: attention-specific ops, layer norm, multi-engine execution, memory
  optimizations (double buffering, tiling).
- **V4**: AI-powered engineering tools (waveform/regression/coverage/perf
  agents) built on top of the artifacts this repo produces.

## 7. Known deliberate imperfections

This RTL contains intentionally injected bugs used to exercise the
verification environment -- see
[`docs/verification/bug_list.md`](../verification/bug_list.md) for the
catalog (populated as each block lands). The build/regression
*infrastructure* is expected to run cleanly; specific bug-hunting tests are
expected to fail and that failure is the intended signal.
