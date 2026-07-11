// Performance Monitor Unit: free-running event counters exposed over
// AXI4-Lite as the `pmu` register block (docs/register_map/tpe_regs.yaml),
// per docs/architecture/tpe_architecture_spec.md section 3.6.
//
// Same flat-port, single-outstanding-transaction AXI4-Lite slave pattern as
// tpe_cmd_proc.sv (AWVALID+WVALID presented together, one transaction at a
// time) -- reused here rather than factored into a shared base module,
// since each block's register file is small and bespoke enough that a
// generic AXI4-Lite register-file wrapper would need almost as much per-
// register plumbing as just writing the read/write mux directly (the same
// call made for tpe_cmd_proc).
//
// All six counters are gated by CTRL.ENABLE and cleared by CTRL.
// RESET_COUNTERS (level-sensitive: counters stay pinned at 0 for as long as
// software holds RESET_COUNTERS high, matching a typical "hold to reset"
// counter-bank convention). Event inputs come from tpe_scheduler (this is
// an integration-level view of activity, not a per-block one -- see
// tpe_top.sv for how these are wired).
module tpe_pmu
  import tpe_pkg::*;
  import tpe_regs_pkg::*;
(
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

    // Event inputs (see tpe_scheduler.sv for exact per-signal semantics)
    input logic mac_active,        // MAC array busy computing this cycle
    input logic dma_wait,          // scheduler stalled waiting on DMA this cycle
    input logic sched_stall,       // scheduler has work but hasn't started it yet
    input logic sched_idle,        // no in-flight command, none queued
    input logic dispatch_start,    // a command's dispatch-latency window begins this cycle
    input logic cmd_done_valid     // a command's dispatch-latency window ends this cycle
);

  // ---- Register storage ---------------------------------------------------
  logic ctrl_enable_q;
  logic ctrl_reset_counters_q;

  logic [31:0] cycle_count_q;
  logic [31:0] mac_active_count_q;
  logic [31:0] dma_wait_count_q;
  logic [31:0] sched_stall_count_q;
  logic [31:0] idle_count_q;
  logic [31:0] cmd_latency_last_q;

  logic        dispatch_active_q;
  logic [31:0] latency_ctr_q;

  wire counting = ctrl_enable_q && !ctrl_reset_counters_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count_q       <= '0;
      mac_active_count_q  <= '0;
      dma_wait_count_q    <= '0;
      sched_stall_count_q <= '0;
      idle_count_q        <= '0;
      cmd_latency_last_q  <= '0;
      dispatch_active_q   <= 1'b0;
      latency_ctr_q        <= '0;
    end else if (ctrl_reset_counters_q) begin
      cycle_count_q       <= '0;
      mac_active_count_q  <= '0;
      dma_wait_count_q    <= '0;
      sched_stall_count_q <= '0;
      idle_count_q        <= '0;
      dispatch_active_q   <= 1'b0;
      latency_ctr_q        <= '0;
      // cmd_latency_last_q deliberately not cleared -- it reports the last
      // *completed* command's latency, which RESET_COUNTERS (a live-
      // counter reset) shouldn't erase, same rationale as a "last value"
      // register in any perf-counter bank.
    end else if (counting) begin
      cycle_count_q <= cycle_count_q + 32'd1;
      if (mac_active) mac_active_count_q <= mac_active_count_q + 32'd1;
      if (dma_wait) dma_wait_count_q <= dma_wait_count_q + 32'd1;
      if (sched_stall) sched_stall_count_q <= sched_stall_count_q + 32'd1;
      if (sched_idle) idle_count_q <= idle_count_q + 32'd1;

      // ---- Per-command dispatch latency ----------------------------------
      if (dispatch_start) begin
        dispatch_active_q <= 1'b1;
        latency_ctr_q      <= 32'd1;  // this cycle is the first counted cycle
      end else if (dispatch_active_q) begin
        latency_ctr_q <= latency_ctr_q + 32'd1;
      end

      if (cmd_done_valid) begin
        // BUG (#7, see docs/verification/bug_list.md): this cycle's
        // increment above (dispatch_active_q branch) hasn't landed in
        // latency_ctr_q yet -- nonblocking assignments both read the *old*
        // value, so capturing latency_ctr_q here misses the completion
        // cycle itself and undercounts by exactly 1. Should be
        // `latency_ctr_q + 32'd1`.
        cmd_latency_last_q <= latency_ctr_q;
        dispatch_active_q  <= 1'b0;
      end
    end
  end

  // ---- AXI4-Lite slave FSM (write) ----------------------------------------
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
    if (!rst_n) begin
      ctrl_enable_q         <= 1'b0;
      ctrl_reset_counters_q <= 1'b0;
    end else if (do_write && s_awaddr == PMU_CTRL_ADDR) begin
      ctrl_enable_q         <= s_wdata[PMU_CTRL_ENABLE_MSB];
      ctrl_reset_counters_q <= s_wdata[PMU_CTRL_RESET_COUNTERS_MSB];
    end
  end

  // ---- AXI4-Lite slave FSM (read) -----------------------------------------
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

  always_comb begin
    case (raddr_q)
      PMU_CTRL_ADDR:             s_rdata = {30'b0, ctrl_reset_counters_q, ctrl_enable_q};
      PMU_CYCLE_COUNT_ADDR:       s_rdata = cycle_count_q;
      PMU_MAC_ACTIVE_COUNT_ADDR:  s_rdata = mac_active_count_q;
      PMU_DMA_WAIT_COUNT_ADDR:    s_rdata = dma_wait_count_q;
      PMU_SCHED_STALL_COUNT_ADDR: s_rdata = sched_stall_count_q;
      PMU_IDLE_COUNT_ADDR:        s_rdata = idle_count_q;
      PMU_CMD_LATENCY_LAST_ADDR:  s_rdata = cmd_latency_last_q;
      default:                    s_rdata = 32'h0;
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

endmodule
