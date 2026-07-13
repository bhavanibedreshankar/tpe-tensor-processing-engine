// Debug infrastructure: per-command trace buffer + latched last-error
// capture, exposed over AXI4-Lite as the `debug` register block
// (docs/register_map/tpe_regs.yaml), per
// docs/architecture/tpe_architecture_spec.md section 3.7.
//
// Same flat-port, single-outstanding AXI4-Lite slave pattern as
// tpe_cmd_proc.sv/tpe_pmu.sv. One extra read state (R_POP_WAIT) vs. those
// two: TRACE_RDATA's read is a *popping* read (the FIFO's registered output
// needs one extra cycle to become valid after rd_en, see
// rtl/common/sync_fifo.sv's own header comment), so a plain address-latch-
// then-return isn't enough for that one register the way it is for every
// other read in this repo so far.
module tpe_debug
  import tpe_pkg::*;
  import tpe_regs_pkg::*;
#(
    parameter int TRACE_DEPTH = 16
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

    // Scheduler completion feed
    input logic        sched_done_valid,
    input logic [11:0] sched_done_tag,
    input cmd_status_e sched_done_status,
    input cmd_opcode_e sched_done_opcode
);

  // ---- Register storage ----------------------------------------------------
  logic ctrl_trace_enable_q;

  logic [31:0] error_code_q;
  logic [31:0] error_tag_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      error_code_q <= '0;
      error_tag_q  <= '0;
    end else if (sched_done_valid && sched_done_status != STAT_OK) begin
      error_code_q <= 32'(sched_done_status);
      error_tag_q  <= 32'(sched_done_tag);
    end
  end

  // ---- Trace FIFO -----------------------------------------------------------
  localparam int TraceBits = 4 /*opcode*/ + 12 /*tag*/ + 3 /*status*/;

  logic [TraceBits-1:0] trace_wr_data, trace_rd_data;
  logic trace_wr_en, trace_full, trace_rd_en, trace_rd_valid, trace_empty;
  logic [$clog2(TRACE_DEPTH):0] trace_count;

  assign trace_wr_data = {3'(sched_done_status), sched_done_tag, 4'(sched_done_opcode)};
  assign trace_wr_en   = sched_done_valid && ctrl_trace_enable_q;

  sync_fifo #(
      .DATA_WIDTH(TraceBits),
      .DEPTH     (TRACE_DEPTH)
  ) u_trace_fifo (
      .clk     (clk),
      .rst_n   (rst_n),
      .wr_en   (trace_wr_en),
      .wr_data (trace_wr_data),
      .full    (trace_full),
      .rd_en   (trace_rd_en),
      .rd_data (trace_rd_data),
      .rd_valid(trace_rd_valid),
      .empty   (trace_empty),
      .count   (trace_count)
  );

  // ---- AXI4-Lite slave FSM (write) ------------------------------------------
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ctrl_trace_enable_q <= 1'b0;
    else if (do_write && s_awaddr == DEBUG_CTRL_ADDR) begin
      ctrl_trace_enable_q <= s_wdata[DEBUG_CTRL_TRACE_ENABLE_MSB];
    end
  end

  // ---- AXI4-Lite slave FSM (read) -------------------------------------------
  // R_POP_WAIT: entered only for a TRACE_RDATA read, gives sync_fifo's
  // registered rd_data one cycle to become valid after the rd_en pulse
  // issued on the R_IDLE->R_POP_WAIT transition, before R_DATA presents it.
  typedef enum logic [1:0] {R_IDLE, R_POP_WAIT, R_DATA} rstate_e;
  rstate_e rstate_q, rstate_d;

  logic [AXIL_ADDR_WIDTH-1:0] raddr_q;
  wire is_trace_rdata = (s_araddr == DEBUG_TRACE_RDATA_ADDR);

  assign s_arready = (rstate_q == R_IDLE);
  assign trace_rd_en = (rstate_q == R_IDLE) && s_arvalid && is_trace_rdata;

  always_comb begin
    rstate_d = rstate_q;
    case (rstate_q)
      R_IDLE:      if (s_arvalid) rstate_d = is_trace_rdata ? R_POP_WAIT : R_DATA;
      R_POP_WAIT:  rstate_d = R_DATA;
      R_DATA:      if (s_rready) rstate_d = R_IDLE;
      default:     rstate_d = R_IDLE;
    endcase
  end

  assign s_rvalid = (rstate_q == R_DATA);
  assign s_rresp  = 2'b00;

  logic [31:0] trace_status_word;
  assign trace_status_word = {19'b0, 11'(trace_count), trace_full, trace_empty};

  always_comb begin
    case (raddr_q)
      DEBUG_CTRL_ADDR:          s_rdata = {31'b0, ctrl_trace_enable_q};
      DEBUG_TRACE_STATUS_ADDR:  s_rdata = trace_status_word;
      DEBUG_TRACE_RDATA_ADDR:   s_rdata = {13'b0, trace_rd_data};
      DEBUG_ERROR_CODE_ADDR:    s_rdata = error_code_q;
      DEBUG_ERROR_TAG_ADDR:     s_rdata = error_tag_q;
      default:                  s_rdata = 32'h0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) raddr_q <= '0;
    else if (rstate_q == R_IDLE && s_arvalid) raddr_q <= s_araddr;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wstate_q <= W_IDLE;
      rstate_q <= R_IDLE;
    end else begin
      wstate_q <= wstate_d;
      rstate_q <= rstate_d;
    end
  end

  // ---- Debug logging (see rtl/include/tpe_verbosity.svh) -----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // no state to reset -- debug prints only
    end else begin
      if (sched_done_valid && sched_done_status != STAT_OK) begin
        `TPE_LOG_CMD_LOW("debug", sched_done_tag, sched_done_opcode,
                          $sformatf("error latched: status=%0s", sched_done_status.name()));
      end
      if (trace_wr_en) begin
        `TPE_LOG_CMD_MEDIUM("debug", sched_done_tag, sched_done_opcode,
                             $sformatf("trace: status=%0s", sched_done_status.name()));
      end else if (sched_done_valid && !ctrl_trace_enable_q) begin
        `TPE_LOG_DEBUG("debug", "trace dropped: trace disabled");
      end
      if (do_write && s_awaddr == DEBUG_CTRL_ADDR) begin
        `TPE_LOG_HIGH("debug", $sformatf("ctrl write trace_enable=%0b",
                                         s_wdata[DEBUG_CTRL_TRACE_ENABLE_MSB]));
      end
    end
  end

endmodule
