// Command Processor: the accelerator's "front door". AXI4-Lite MMIO slave
// implementing the `cp` register block (docs/register_map/tpe_regs.yaml,
// generated into tpe_regs_pkg.sv), a command-staging register set, and the
// command FIFO the Scheduler drains. Per
// docs/architecture/tpe_architecture_spec.md section 3.1.
//
// V1 AXI4-Lite simplification: this slave expects AWVALID and WVALID to be
// presented *together* (both required before a write is accepted) rather
// than supporting independent AW/W channel timing -- a common
// simplification for lightweight register slaves, and consistent with how
// verif/cocotb_tb/env/axi4_lite_agent.py drives it. One outstanding
// transaction at a time (no pipelining), matching V1's overall scope.
//
// V1 implementation note: only `cp`, `pmu` (M5), and `debug` (M5) are real
// AXI4-Lite-visible register banks -- see tpe_top.sv's host MMIO router.
// `dma`/`matrix_engine`'s entries in the register map YAML document the
// full conceptual programmer's view; in this implementation the Scheduler
// drives those blocks directly over plain control signals rather than
// through a second layer of AXI4-Lite decoding (see tpe_scheduler.sv).
module tpe_cmd_proc
  import tpe_pkg::*;
  import tpe_regs_pkg::*;
#(
    parameter int CMD_FIFO_DEPTH = 4
) (
    input logic clk,
    input logic rst_n,

    // AXI4-Lite slave (host MMIO)
    input  logic                        s_awvalid,
    input  logic [AXIL_ADDR_WIDTH-1:0]  s_awaddr,
    output logic                        s_awready,
    input  logic                        s_wvalid,
    input  logic [AXIL_DATA_WIDTH-1:0]  s_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0]  s_wstrb,
    output logic                        s_wready,
    output logic                        s_bvalid,
    output logic [1:0]                  s_bresp,
    input  logic                        s_bready,
    input  logic                        s_arvalid,
    input  logic [AXIL_ADDR_WIDTH-1:0]  s_araddr,
    output logic                        s_arready,
    output logic                        s_rvalid,
    output logic [AXIL_DATA_WIDTH-1:0]  s_rdata,
    output logic [1:0]                  s_rresp,
    input  logic                        s_rready,

    output logic irq,

    // Scheduler interface
    output logic         cmd_fifo_empty,
    input  logic         cmd_fifo_rd_en,
    output logic         cmd_fifo_rd_valid,
    output tpe_command_t cmd_fifo_rd_data,

    input logic        sched_done_valid,
    input logic [11:0] sched_done_tag,
    input cmd_status_e sched_done_status,
    input logic        sched_busy
);

  // ---- Register storage -------------------------------------------------
  logic ctrl_enable_q;
  logic soft_reset_pulse;

  logic [3:0]  stg_opcode_q;
  logic [11:0] stg_tag_q;
  logic [SRAM_ADDR_WIDTH-1:0] stg_sram_addr_q;
  logic [AXI_ADDR_WIDTH-1:0]  stg_mem_addr_q;
  logic [TILE_DIM_WIDTH-1:0]  stg_dim_m_q, stg_dim_k_q, stg_dim_n_q;

  logic [1:0] irq_status_q;  // {CMD_ERROR, CMD_DONE}
  logic [1:0] irq_enable_q;

  logic        last_status_valid_q;
  cmd_status_e last_status_q;

  logic soft_reset_active;  // synchronous reset pulse for the FIFO

  // ---- Command FIFO -------------------------------------------------------
  localparam int CmdBits = $bits(tpe_command_t);

  logic                  fifo_wr_en, fifo_full;
  logic [CmdBits-1:0]    fifo_wr_data;
  logic [CmdBits-1:0]    fifo_rd_data_bits;
  logic [$clog2(CMD_FIFO_DEPTH):0] fifo_count;

  tpe_command_t push_cmd;
  assign push_cmd.opcode    = cmd_opcode_e'(stg_opcode_q);
  assign push_cmd.tag       = stg_tag_q;
  assign push_cmd.sram_addr = stg_sram_addr_q;
  assign push_cmd.mem_addr  = stg_mem_addr_q;
  assign push_cmd.dim_m     = stg_dim_m_q;
  assign push_cmd.dim_k     = stg_dim_k_q;
  assign push_cmd.dim_n     = stg_dim_n_q;
  assign fifo_wr_data       = push_cmd;

  sync_fifo #(
      .DATA_WIDTH(CmdBits),
      .DEPTH     (CMD_FIFO_DEPTH)
  ) u_cmd_fifo (
      .clk     (clk),
      .rst_n   (rst_n && !soft_reset_active),
      .wr_en   (fifo_wr_en),
      .wr_data (fifo_wr_data),
      .full    (fifo_full),
      .rd_en   (cmd_fifo_rd_en),
      .rd_data (fifo_rd_data_bits),
      .rd_valid(cmd_fifo_rd_valid),
      .empty   (cmd_fifo_empty),
      .count   (fifo_count)
  );

  assign cmd_fifo_rd_data = tpe_command_t'(fifo_rd_data_bits);

  // ---- AXI4-Lite slave FSM (write) --------------------------------------
  typedef enum logic [1:0] {W_IDLE, W_RESP} wstate_e;
  wstate_e wstate_q, wstate_d;

  assign s_awready = (wstate_q == W_IDLE);
  assign s_wready  = (wstate_q == W_IDLE);

  wire do_write = (wstate_q == W_IDLE) && s_awvalid && s_wvalid;

  always_comb begin
    wstate_d = wstate_q;
    case (wstate_q)
      W_IDLE: if (do_write) wstate_d = W_RESP;
      W_RESP: if (s_bready) wstate_d = W_IDLE;
      default: wstate_d = W_IDLE;
    endcase
  end

  assign s_bvalid = (wstate_q == W_RESP);
  assign s_bresp  = 2'b00;

  // ---- AXI4-Lite slave FSM (read) ---------------------------------------
  typedef enum logic [1:0] {R_IDLE, R_DATA} rstate_e;
  rstate_e rstate_q, rstate_d;

  logic [AXIL_ADDR_WIDTH-1:0] raddr_q;

  assign s_arready = (rstate_q == R_IDLE);

  always_comb begin
    rstate_d = rstate_q;
    case (rstate_q)
      R_IDLE: if (s_arvalid) rstate_d = R_DATA;
      R_DATA: if (s_rready) rstate_d = R_IDLE;
      default: rstate_d = R_IDLE;
    endcase
  end

  assign s_rvalid = (rstate_q == R_DATA);
  assign s_rresp  = 2'b00;

  // ---- Read data mux -----------------------------------------------------
  logic [AXIL_DATA_WIDTH-1:0] status_word;
  assign status_word = {
    25'b0,
    last_status_valid_q ? last_status_q : STAT_OK,
    1'b0,  // reserved
    cmd_fifo_empty,
    fifo_full,
    sched_busy
  };

  always_comb begin
    case (raddr_q)
      CP_VERSION_ADDR:        s_rdata = CP_VERSION_RESET;
      CP_CTRL_ADDR:           s_rdata = {30'b0, 1'b0, ctrl_enable_q};
      CP_STATUS_ADDR:         s_rdata = status_word;
      CP_CMD_OPCODE_TAG_ADDR: s_rdata = {16'b0, stg_tag_q, stg_opcode_q};
      CP_CMD_SRAM_ADDR_ADDR:  s_rdata = {{(AXIL_DATA_WIDTH - SRAM_ADDR_WIDTH) {1'b0}}, stg_sram_addr_q};
      CP_CMD_MEM_ADDR_ADDR:   s_rdata = stg_mem_addr_q;
      CP_CMD_DIM_MK_ADDR:     s_rdata = {{(16 - TILE_DIM_WIDTH) {1'b0}}, stg_dim_k_q, {(16 - TILE_DIM_WIDTH) {1'b0}}, stg_dim_m_q};
      CP_CMD_DIM_N_ADDR:      s_rdata = {16'b0, {(16 - TILE_DIM_WIDTH) {1'b0}}, stg_dim_n_q};
      CP_IRQ_STATUS_ADDR:     s_rdata = {30'b0, irq_status_q};
      CP_IRQ_ENABLE_ADDR:     s_rdata = {30'b0, irq_enable_q};
      default:                s_rdata = 32'h0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) raddr_q <= '0;
    else if (rstate_q == R_IDLE && s_arvalid) raddr_q <= s_araddr;
  end

  // ---- Register writes ---------------------------------------------------
  assign soft_reset_active = do_write && (s_awaddr == CP_CTRL_ADDR) && s_wdata[CP_CTRL_SOFT_RESET_MSB];
  assign fifo_wr_en = do_write && (s_awaddr == CP_CMD_PUSH_ADDR) && s_wdata[CP_CMD_PUSH_PUSH_MSB]
                       && ctrl_enable_q && !fifo_full;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_enable_q   <= 1'b0;
      stg_opcode_q    <= '0;
      stg_tag_q       <= '0;
      stg_sram_addr_q <= '0;
      stg_mem_addr_q  <= '0;
      stg_dim_m_q     <= '0;
      stg_dim_k_q     <= '0;
      stg_dim_n_q     <= '0;
      irq_enable_q    <= '0;
    end else if (do_write) begin
      case (s_awaddr)
        CP_CTRL_ADDR:           ctrl_enable_q <= s_wdata[CP_CTRL_ENABLE_MSB];
        CP_CMD_OPCODE_TAG_ADDR: begin
          stg_opcode_q <= s_wdata[CP_CMD_OPCODE_TAG_OPCODE_MSB:CP_CMD_OPCODE_TAG_OPCODE_LSB];
          stg_tag_q    <= s_wdata[CP_CMD_OPCODE_TAG_TAG_MSB:CP_CMD_OPCODE_TAG_TAG_LSB];
        end
        CP_CMD_SRAM_ADDR_ADDR: stg_sram_addr_q <= s_wdata[SRAM_ADDR_WIDTH-1:0];
        CP_CMD_MEM_ADDR_ADDR:  stg_mem_addr_q  <= s_wdata;
        CP_CMD_DIM_MK_ADDR: begin
          stg_dim_m_q <= s_wdata[CP_CMD_DIM_MK_DIM_M_LSB+TILE_DIM_WIDTH-1:CP_CMD_DIM_MK_DIM_M_LSB];
          stg_dim_k_q <= s_wdata[CP_CMD_DIM_MK_DIM_K_LSB+TILE_DIM_WIDTH-1:CP_CMD_DIM_MK_DIM_K_LSB];
        end
        CP_CMD_DIM_N_ADDR:  stg_dim_n_q  <= s_wdata[CP_CMD_DIM_N_DIM_N_LSB+TILE_DIM_WIDTH-1:CP_CMD_DIM_N_DIM_N_LSB];
        CP_IRQ_ENABLE_ADDR: irq_enable_q <= s_wdata[1:0];
        default: ;
      endcase
    end
  end

  // ---- IRQ status: set by scheduler completion, W1C by host --------------
  // A same-cycle completion always wins over a host clear (necessarily of
  // *older* status): the HW-set assignments below run after the W1C clear
  // in program order, so they're what's actually scheduled for bits where
  // both would otherwise apply in the same cycle.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      irq_status_q        <= '0;
      last_status_valid_q <= 1'b0;
      last_status_q       <= STAT_OK;
    end else begin
      if (sched_done_valid) begin
        last_status_valid_q <= 1'b1;
        last_status_q       <= sched_done_status;
      end

      if (do_write && (s_awaddr == CP_IRQ_STATUS_ADDR)) begin
        irq_status_q <= irq_status_q & ~{2{s_wdata[0]}};
      end

      if (sched_done_valid) begin
        irq_status_q[0] <= 1'b1;
        if (sched_done_status != STAT_OK) irq_status_q[1] <= 1'b1;
      end
    end
  end

  assign irq = |(irq_status_q & irq_enable_q);

  // ---- AXI4-Lite state registers ------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wstate_q <= W_IDLE;
      rstate_q <= R_IDLE;
    end else begin
      wstate_q <= wstate_d;
      rstate_q <= rstate_d;
    end
  end

endmodule
