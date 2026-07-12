// TPE global package: shared widths, opcodes and typedefs used across blocks.
// Register offsets/fields live in the *generated* tpe_regs_pkg.sv
// (docs/register_map/tpe_regs.yaml is the source of truth -- see
// tools/regmap_gen.py). Do not hand-edit tpe_regs_pkg.sv.
package tpe_pkg;

  // ---------------------------------------------------------------------
  // Numeric formats
  //
  // V1 uses INT8 operands with INT32 accumulation, matching the classic
  // quantized-inference accelerator datapath (e.g. weight/activation
  // matrices are int8, the systolic accumulator is int32 with saturation
  // on readout). This keeps the datapath narrow (dense MAC array) while
  // giving headroom for K-deep dot products without overflow.
  // ---------------------------------------------------------------------
  parameter int OPERAND_WIDTH    = 8;                    // int8 activations/weights
  parameter int ACCUM_WIDTH      = 32;                   // int32 accumulator
  parameter int OPERAND_SIGNED   = 1;

  // ---------------------------------------------------------------------
  // Matrix Compute Engine geometry (parametrizable, default 16x16 = 256 MACs
  // per the architecture overview; scales to 32x32/64x64 without interface
  // changes).
  // ---------------------------------------------------------------------
  parameter int MAC_ARRAY_ROWS   = 16;
  parameter int MAC_ARRAY_COLS   = 16;
  parameter int MAX_TILE_DIM     = 256;                  // max M/K/N per tile op
  parameter int TILE_DIM_WIDTH   = $clog2(MAX_TILE_DIM + 1);

  // ---------------------------------------------------------------------
  // Local SRAM (scratchpad)
  // ---------------------------------------------------------------------
  parameter int SRAM_DATA_WIDTH  = 128;                  // bits per row (16B)
  parameter int SRAM_DEPTH       = 4096;                 // rows -> 64KB total
  parameter int SRAM_ADDR_WIDTH  = $clog2(SRAM_DEPTH);
  parameter int SRAM_STRB_WIDTH  = SRAM_DATA_WIDTH / 8;

  // ---------------------------------------------------------------------
  // System-level address/data widths (AXI-Lite MMIO, AXI4 memory port)
  // ---------------------------------------------------------------------
  parameter int AXI_ADDR_WIDTH   = 32;
  parameter int AXI_DATA_WIDTH   = 128;
  parameter int AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8;
  parameter int AXI_ID_WIDTH     = 4;
  parameter int AXI_LEN_WIDTH    = 8;                    // AXI4 burst length field

  parameter int AXIL_ADDR_WIDTH  = 16;                   // MMIO register space
  parameter int AXIL_DATA_WIDTH  = 32;
  parameter int AXIL_STRB_WIDTH  = AXIL_DATA_WIDTH / 8;

  // ---------------------------------------------------------------------
  // Command Processor opcodes
  //
  // Software flow (see docs/architecture/tpe_architecture_spec.md):
  //   host writes a command word + operands to MMIO -> Command Processor
  //   decodes -> pushes into the Scheduler -> DMA / Matrix Engine execute
  //   -> completion IRQ.
  // ---------------------------------------------------------------------
  typedef enum logic [3:0] {
    CMD_NOP         = 4'h0,
    CMD_LOAD_WEIGHT = 4'h1,   // DMA DDR -> SRAM (weight region)
    CMD_LOAD_ACT    = 4'h2,   // DMA DDR -> SRAM (activation region)
    CMD_MATMUL      = 4'h3,   // C = A x B + C on the Matrix Compute Engine
    CMD_STORE       = 4'h4,   // DMA SRAM -> DDR (output region)
    CMD_BARRIER     = 4'h5,   // wait for all in-flight ops to drain
    CMD_IRQ_TEST    = 4'hE,   // debug: force an interrupt
    CMD_INVALID     = 4'hF
  } cmd_opcode_e;

  typedef struct packed {
    cmd_opcode_e            opcode;
    logic [11:0]            tag;          // caller-assigned id, echoed on completion
    logic [SRAM_ADDR_WIDTH-1:0] sram_addr;
    logic [AXI_ADDR_WIDTH-1:0]  mem_addr;
    logic [TILE_DIM_WIDTH-1:0]  dim_m;
    logic [TILE_DIM_WIDTH-1:0]  dim_k;
    logic [TILE_DIM_WIDTH-1:0]  dim_n;
  } tpe_command_t;

  // ---------------------------------------------------------------------
  // Completion / error status
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    STAT_OK             = 3'h0,
    STAT_BAD_OPCODE     = 3'h1,
    STAT_BAD_DIM        = 3'h2,
    STAT_SRAM_OOB       = 3'h3,
    STAT_MEM_ERROR      = 3'h4,
    STAT_ACCUM_OVERFLOW = 3'h5
  } cmd_status_e;

  function automatic int unsigned clog2(input int unsigned value);
    int unsigned v;
    begin
      v = value - 1;
      clog2 = 0;
      while (v > 0) begin
        v = v >> 1;
        clog2 = clog2 + 1;
      end
    end
  endfunction

  // ---------------------------------------------------------------------
  // Debug verbosity (rtl/include/tpe_verbosity.svh's `TPE_LOG_* macros) --
  // selected once at runtime via `+VERBOSITY=<LEVEL>` (default NONE, i.e.
  // off: no `$display` output, no behavior/timing change versus before
  // this existed). Names mirror UVM's uvm_verbosity without depending on
  // UVM itself -- this repo's RTL sim doesn't use it. `run_sim -verbosity`
  // sets this plusarg and the C++ golden model's TPE_VERBOSITY env var
  // together (docs/flows/run_sim_flow.md).
  // ---------------------------------------------------------------------
  typedef enum int {
    TPE_VERB_NONE   = 0,
    TPE_VERB_LOW    = 1,
    TPE_VERB_MEDIUM = 2,
    TPE_VERB_HIGH   = 3,
    TPE_VERB_DEBUG  = 4
  } tpe_verbosity_e;

  function automatic tpe_verbosity_e tpe_verbosity();
    static bit initialized = 0;
    static tpe_verbosity_e level = TPE_VERB_NONE;
    string level_str;
    if (!initialized) begin
      if ($value$plusargs("VERBOSITY=%s", level_str)) begin
        case (level_str)
          "LOW":    level = TPE_VERB_LOW;
          "MEDIUM": level = TPE_VERB_MEDIUM;
          "HIGH":   level = TPE_VERB_HIGH;
          "DEBUG":  level = TPE_VERB_DEBUG;
          default:  level = TPE_VERB_NONE;
        endcase
      end
      initialized = 1;
    end
    return level;
  endfunction

  function automatic string tpe_verbosity_name(input tpe_verbosity_e lvl);
    case (lvl)
      TPE_VERB_LOW:    return "LOW";
      TPE_VERB_MEDIUM: return "MEDIUM";
      TPE_VERB_HIGH:   return "HIGH";
      TPE_VERB_DEBUG:  return "DEBUG";
      default:         return "NONE";
    endcase
  endfunction

endpackage : tpe_pkg
