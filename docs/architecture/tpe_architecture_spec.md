# Tensor Processing Engine (TPE) -- Architecture Specification

Status: **V1 in progress** (see [Roadmap](#roadmap) and
[Milestone tracking](../../overview) for scope boundaries).

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
Pulls commands off the command FIFO and arbitrates DMA vs. Matrix Engine
issue so the two can overlap (e.g. prefetch the next tile's weights while
the current tile computes). V1 scope: two-way arbitration between one DMA
channel and the Matrix Engine, dependency tracking via a simple
scoreboard-bit per SRAM region (a command that writes a region blocks a
later command that reads it until the writer completes).

### 3.3 DMA Engine (`rtl/dma/`)
Descriptor-based mover between DDR (AXI4 master) and the Local SRAM
scratchpad. V1 scope: single channel, one descriptor in flight at a time
(`DESC_MEM_ADDR`/`DESC_SRAM_ADDR`/`DESC_LEN`/`DESC_CTRL`). Double buffering
and scatter-gather are called out as V2+ in the original vision doc and are
out of scope here.

### 3.4 Local SRAM / Scratchpad (`rtl/sram/`)
Dual-port, byte-addressable-via-strobe scratchpad (`SRAM_DEPTH` x
`SRAM_DATA_WIDTH` = 4096 x 128b = 64KB). One port serves DMA fill/drain, the
other serves the Matrix Engine's input/output buffers. Deterministic
single-cycle-plus-pipeline-latency access, no cache coherence to verify.

### 3.5 Matrix Compute Engine (`rtl/matrix_engine/`)
Weight-stationary systolic array, default `MAC_ARRAY_ROWS` x
`MAC_ARRAY_COLS` = 16x16 = 256 MACs, computing `C = A x B + C` over tiles up
to `MAX_TILE_DIM` in each of M/K/N. Internally: input buffers -> MAC array
(`rtl/matrix_engine/pe.sv` x N instances) -> accumulator
(`rtl/matrix_engine/accumulator.sv`, int32, saturating) -> output buffer.

### 3.6 Performance Monitor Unit (`rtl/pmu/`)
Free-running counters exposed via the `pmu` register block: cycle count,
MAC-active cycles, DMA-wait cycles, scheduler-stall cycles, idle cycles, and
last-command latency. Counters reset via `PMU_CTRL.RESET_COUNTERS` and can
be gated via `PMU_CTRL.ENABLE`.

### 3.7 Debug Infrastructure (`rtl/debug/`)
Command trace buffer (opcode/tag/status per completed command, popped via
`DEBUG_TRACE_RDATA`) plus latched error code/tag for the most recent error
(`DEBUG_ERROR_CODE`/`DEBUG_ERROR_TAG`). Assertion status is observed through
the simulator's assertion log, not modeled as a register (see the
[verification test plan](../verification/test_plan.md)).

## 4. Interfaces

- **Host MMIO**: AXI4-Lite, `AXIL_ADDR_WIDTH`=16, `AXIL_DATA_WIDTH`=32.
- **DDR memory**: AXI4, `AXI_ADDR_WIDTH`=32, `AXI_DATA_WIDTH`=128,
  `AXI_ID_WIDTH`=4, burst-capable (`AXI_LEN_WIDTH`=8). Defined in
  `rtl/include/axi4_if.sv` / `axi4_lite_if.sv` (added in the DMA milestone).
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
