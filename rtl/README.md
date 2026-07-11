# rtl/

Synthesizable SystemVerilog only -- no testbench code, no SVA, no
covergroups (those live in `verif/sva/` and `verif/coverage/`/inline
covergroups get added per-block starting M2, bound in rather than embedded
where practical to keep this tree pure RTL).

| Directory | Block | Milestone | Status |
|---|---|---|---|
| `include/` | `tpe_pkg.sv` (shared params/typedefs), `tpe_regs_pkg.sv` (generated register map) | M0 | done |
| `common/` | `sync_fifo`, `round_robin_arb`, `dp_ram` -- reusable primitives | M0 | done |
| `sram/` | Local SRAM scratchpad | M1 | done |
| `matrix_engine/` | MAC array (`pe.sv`), accumulator, GEMM control | M2 | done (3 intentional bugs, see bug catalog) |
| `dma/` | Descriptor-based DDR<->SRAM DMA engine | M3 | pending |
| `command_processor/` | AXI4-Lite MMIO, command decode/staging | M4 | pending |
| `scheduler/` | DMA/compute arbitration, dependency tracking | M4 | pending |
| `pmu/` | Performance counters | M5 | pending |
| `debug/` | Command trace buffer, error capture | M5 | pending |
| `top/` | `tpe_top.sv` -- wires everything together | M4 | pending |

`rtl/include/tpe_regs_pkg.sv` is **generated** from
`docs/register_map/tpe_regs.yaml` -- do not hand-edit it; run `make regmap`.
