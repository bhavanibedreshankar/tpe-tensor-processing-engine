// Instruction Scheduler: pops commands from the Command Processor's FIFO
// and dispatches them to the DMA Engine or Matrix Compute Engine, per
// docs/architecture/tpe_architecture_spec.md section 3.2.
//
// V1 simplification (matches the roadmap's own "V2: improved scheduler"
// item): this is a *sequential* dispatcher, not an out-of-order/overlapped
// arbiter -- one command executes fully (through whichever engine it
// targets) before the next is popped. Overlapping DMA prefetch with
// compute is explicitly deferred to V2.
//
// Also owns the "which of matrix_engine's four buffers does the DMA's
// SRAM-side port currently talk to" router select (router_sel), since
// that's purely a function of which command is in flight -- see
// tpe_top.sv for the router itself.
module tpe_scheduler
  import tpe_pkg::*;
#(
    parameter int ROWS = MAC_ARRAY_ROWS,
    parameter int COLS = MAC_ARRAY_COLS,
    parameter int OBUF_CHUNKS_PER_ROW = (COLS * ACCUM_WIDTH) / AXI_DATA_WIDTH
) (
    input logic clk,
    input logic rst_n,

    // Command FIFO pop side (owned by tpe_cmd_proc)
    input  logic          cmd_fifo_empty,
    output logic          cmd_fifo_rd_en,
    input  logic          cmd_fifo_rd_valid,
    input  tpe_command_t  cmd_fifo_rd_data,

    // Completion report to tpe_cmd_proc
    output logic          sched_done_valid,
    output logic [11:0]   sched_done_tag,
    output cmd_status_e   sched_done_status,
    output logic          sched_busy,

    // DMA control
    output logic [AXI_ADDR_WIDTH-1:0]  dma_desc_mem_addr,
    output logic [SRAM_ADDR_WIDTH-1:0] dma_desc_sram_addr,
    output logic [19:0]                dma_desc_len,
    output logic                       dma_desc_dir,
    output logic                       dma_start,
    input  logic                       dma_busy,
    input  logic                       dma_done,
    input  logic                       dma_error,

    // Matrix Engine control
    output logic                      me_start,
    output logic [TILE_DIM_WIDTH-1:0] me_dim_m,
    output logic [TILE_DIM_WIDTH-1:0] me_dim_k,
    output logic [TILE_DIM_WIDTH-1:0] me_dim_n,
    input  logic                      me_busy,
    input  logic                      me_done,
    input  logic                      me_overflow_sticky,

    // SRAM router select: 0=weight_buf, 1=act_buf, 2=seed_buf(unused V1), 3=out_buf
    output logic [1:0] router_sel
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_POP,
    ST_DECODE,
    ST_DISPATCH_DMA,
    ST_WAIT_DMA,
    ST_DISPATCH_ME,
    ST_WAIT_ME,
    ST_COMPLETE
  } state_e;

  state_e state_q, state_d;

  tpe_command_t cmd_q;
  cmd_status_e status_q;

  localparam logic [1:0] RouterWeight = 2'd0;
  localparam logic [1:0] RouterAct = 2'd1;
  localparam logic [1:0] RouterSeed = 2'd2;
  localparam logic [1:0] RouterOut = 2'd3;

  logic [1:0] router_sel_q;
  assign router_sel = router_sel_q;

  wire dim_ok_for_matmul = (cmd_q.dim_k <= TILE_DIM_WIDTH'(ROWS)) && (cmd_q.dim_n < TILE_DIM_WIDTH'(COLS));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= ST_IDLE;
      cmd_q        <= '0;
      status_q     <= STAT_OK;
      router_sel_q <= RouterWeight;
    end else begin
      state_q <= state_d;

      if (state_q == ST_POP && cmd_fifo_rd_valid) begin
        cmd_q <= cmd_fifo_rd_data;
      end

      if (state_q == ST_DECODE) begin
        unique case (cmd_q.opcode)
          CMD_LOAD_WEIGHT: router_sel_q <= RouterWeight;
          CMD_LOAD_ACT:    router_sel_q <= RouterAct;
          CMD_STORE:       router_sel_q <= RouterOut;
          default:         router_sel_q <= router_sel_q;
        endcase

        unique case (cmd_q.opcode)
          CMD_NOP, CMD_BARRIER, CMD_IRQ_TEST: status_q <= STAT_OK;
          CMD_MATMUL: status_q <= dim_ok_for_matmul ? STAT_OK : STAT_BAD_DIM;
          CMD_LOAD_WEIGHT, CMD_LOAD_ACT, CMD_STORE: status_q <= STAT_OK;
          default: status_q <= STAT_BAD_OPCODE;
        endcase
      end else if (state_q == ST_WAIT_DMA && dma_done) begin
        status_q <= dma_error ? STAT_MEM_ERROR : STAT_OK;
      end else if (state_q == ST_WAIT_ME && me_done) begin
        status_q <= me_overflow_sticky ? STAT_ACCUM_OVERFLOW : STAT_OK;
      end
    end
  end

  always_comb begin
    state_d = state_q;
    case (state_q)
      // cmd_fifo_rd_en pulses exactly once, gated by state_q==ST_IDLE
      // below -- ST_POP must not re-assert it (sync_fifo has no notion of
      // "pop already requested," it would advance twice).
      ST_IDLE:  if (!cmd_fifo_empty) state_d = ST_POP;
      ST_POP:   if (cmd_fifo_rd_valid) state_d = ST_DECODE;
      ST_DECODE: begin
        unique case (cmd_q.opcode)
          CMD_NOP, CMD_BARRIER, CMD_IRQ_TEST: state_d = ST_COMPLETE;
          CMD_LOAD_WEIGHT, CMD_LOAD_ACT, CMD_STORE: state_d = ST_DISPATCH_DMA;
          CMD_MATMUL: state_d = dim_ok_for_matmul ? ST_DISPATCH_ME : ST_COMPLETE;
          default: state_d = ST_COMPLETE;  // bad opcode
        endcase
      end
      ST_DISPATCH_DMA: state_d = ST_WAIT_DMA;
      ST_WAIT_DMA:     if (dma_done) state_d = ST_COMPLETE;
      ST_DISPATCH_ME:  state_d = ST_WAIT_ME;
      ST_WAIT_ME:      if (me_done) state_d = ST_COMPLETE;
      ST_COMPLETE:     state_d = ST_IDLE;
      default:         state_d = ST_IDLE;
    endcase
  end

  // ---- Command FIFO pop -------------------------------------------------
  // Pulses exactly once (the ST_IDLE->ST_POP transition cycle); ST_POP
  // itself only waits for cmd_fifo_rd_valid, it must not re-request.
  assign cmd_fifo_rd_en = (state_q == ST_IDLE) && !cmd_fifo_empty;

  // ---- DMA dispatch -------------------------------------------------------
  logic [19:0] len_bytes;
  always_comb begin
    unique case (cmd_q.opcode)
      CMD_LOAD_WEIGHT: len_bytes = 20'(cmd_q.dim_k) << 4;
      CMD_LOAD_ACT:    len_bytes = 20'(cmd_q.dim_m) << 4;
      CMD_STORE:       len_bytes = (20'(cmd_q.dim_m) * 20'(OBUF_CHUNKS_PER_ROW)) << 4;
      default:          len_bytes = '0;
    endcase
  end

  logic [SRAM_ADDR_WIDTH-1:0] sram_row_addr;
  assign sram_row_addr = (cmd_q.opcode == CMD_STORE)
      ? (cmd_q.sram_addr * SRAM_ADDR_WIDTH'(OBUF_CHUNKS_PER_ROW))
      : cmd_q.sram_addr;

  assign dma_desc_mem_addr  = cmd_q.mem_addr;
  assign dma_desc_sram_addr = sram_row_addr;
  assign dma_desc_len       = len_bytes;
  assign dma_desc_dir       = (cmd_q.opcode == CMD_STORE);
  assign dma_start          = (state_q == ST_DISPATCH_DMA);

  // ---- Matrix Engine dispatch --------------------------------------------
  assign me_dim_m = cmd_q.dim_m;
  assign me_dim_k = cmd_q.dim_k;
  assign me_dim_n = cmd_q.dim_n;
  assign me_start = (state_q == ST_DISPATCH_ME);

  // ---- Completion / status -----------------------------------------------
  assign sched_done_valid  = (state_q == ST_COMPLETE);
  assign sched_done_tag    = cmd_q.tag;
  assign sched_done_status = status_q;
  assign sched_busy        = (state_q != ST_IDLE);

endmodule
