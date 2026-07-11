// Behavioral AXI4 slave modeling external DDR memory for testbenches.
// NOT synthesizable production RTL (hence living under verif/, not rtl/) --
// this is what rtl/dma/tpe_dma.sv's AXI4 master talks to in simulation.
// INCR bursts only (matches tpe_dma.sv, the only master in this repo).
// Always-ready on AR/AW (no artificial backpressure in V1 -- a real DDR
// model with variable latency is a natural V2 extension once there's a
// scheduler that needs to be tested against it). Read and write bursts are
// never concurrent in this model (write takes priority on the shared
// storage port) since tpe_dma processes one descriptor -- one direction --
// at a time and never issues both simultaneously.
//
// Storage is a plain rtl/common/dp_ram.sv: port A is a backdoor
// (dp_ram-style, SyncPortAgent-compatible) test-side port for preloading
// DDR content and reading back results without going through AXI at all;
// port B is driven by this module's internal AXI FSMs.
module axi4_ddr_model #(
    parameter int ADDR_WIDTH     = 32,
    parameter int DATA_WIDTH     = 128,
    parameter int DEPTH          = 4096,
    parameter int STRB_WIDTH     = DATA_WIDTH / 8,
    parameter int ID_WIDTH       = 4,
    parameter int MEM_ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // AXI4 slave -- write address
    input  logic                  awvalid,
    input  logic [ADDR_WIDTH-1:0] awaddr,
    input  logic [           7:0] awlen,
    input  logic [  ID_WIDTH-1:0] awid,
    output logic                  awready,

    // AXI4 slave -- write data
    input  logic                   wvalid,
    input  logic [DATA_WIDTH-1:0]  wdata,
    input  logic [STRB_WIDTH-1:0]  wstrb,
    input  logic                   wlast,
    output logic                   wready,

    // AXI4 slave -- write response
    output logic                bvalid,
    output logic [         1:0] bresp,
    output logic [ID_WIDTH-1:0] bid,
    input  logic                bready,

    // AXI4 slave -- read address
    input  logic                  arvalid,
    input  logic [ADDR_WIDTH-1:0] araddr,
    input  logic [           7:0] arlen,
    input  logic [  ID_WIDTH-1:0] arid,
    output logic                  arready,

    // AXI4 slave -- read data
    output logic                   rvalid,
    output logic [DATA_WIDTH-1:0]  rdata,
    output logic [           1:0]  rresp,
    output logic                   rlast,
    output logic [  ID_WIDTH-1:0]  rid,
    input  logic                   rready,

    // Backdoor test port (dp_ram port-A convention)
    input  logic                      bd_en,
    input  logic                      bd_we,
    input  logic [    STRB_WIDTH-1:0] bd_strb,
    input  logic [MEM_ADDR_WIDTH-1:0] bd_addr,
    input  logic [    DATA_WIDTH-1:0] bd_wdata,
    output logic [    DATA_WIDTH-1:0] bd_rdata
);

  localparam int BeatBytes = DATA_WIDTH / 8;
  localparam int RowShift = $clog2(BeatBytes);

  logic                      mem_b_en;
  logic                      mem_b_we;
  logic [STRB_WIDTH-1:0]     mem_b_strb;
  logic [MEM_ADDR_WIDTH-1:0] mem_b_addr;
  logic [DATA_WIDTH-1:0]     mem_b_wdata;
  logic [DATA_WIDTH-1:0]     mem_b_rdata;

  dp_ram #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(MEM_ADDR_WIDTH),
      .STRB_WIDTH(STRB_WIDTH)
  ) u_mem (
      .clk    (clk),
      .a_en   (bd_en),
      .a_we   (bd_we),
      .a_strb (bd_strb),
      .a_addr (bd_addr),
      .a_wdata(bd_wdata),
      .a_rdata(bd_rdata),
      .b_en   (mem_b_en),
      .b_we   (mem_b_we),
      .b_strb (mem_b_strb),
      .b_addr (mem_b_addr),
      .b_wdata(mem_b_wdata),
      .b_rdata(mem_b_rdata)
  );

  // ---- Write channel FSM ---------------------------------------------
  typedef enum logic [1:0] {
    W_IDLE,
    W_BURST,
    W_RESP
  } wstate_e;
  wstate_e wstate_q, wstate_d;

  logic [MEM_ADDR_WIDTH-1:0] waddr_q;
  logic [ID_WIDTH-1:0] awid_q;

  assign awready = (wstate_q == W_IDLE);
  assign wready  = (wstate_q == W_BURST);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wstate_q <= W_IDLE;
      waddr_q  <= '0;
      awid_q   <= '0;
    end else begin
      wstate_q <= wstate_d;
      if (wstate_q == W_IDLE && awvalid) begin
        waddr_q <= awaddr[MEM_ADDR_WIDTH+RowShift-1:RowShift];
        awid_q  <= awid;
      end else if (wstate_q == W_BURST && wvalid) begin
        waddr_q <= waddr_q + 1'b1;
      end
    end
  end

  always_comb begin
    wstate_d = wstate_q;
    case (wstate_q)
      W_IDLE:  if (awvalid) wstate_d = W_BURST;
      W_BURST: if (wvalid && wlast) wstate_d = W_RESP;
      W_RESP:  if (bready) wstate_d = W_IDLE;
      default: wstate_d = W_IDLE;
    endcase
  end

  assign bvalid = (wstate_q == W_RESP);
  assign bresp  = 2'b00;  // OKAY
  assign bid    = awid_q;

  wire write_active = (wstate_q == W_BURST) && wvalid;

  // ---- Read channel FSM ------------------------------------------------
  // dp_ram's read is registered (1-cycle latency): a read issued this
  // cycle (mem_r_en) produces valid data visible *next* cycle. read_pend_q
  // tracks "is there a beat sitting in mem_b_rdata waiting for rready".
  typedef enum logic {
    R_IDLE,
    R_BURST
  } rstate_e;
  rstate_e rstate_q, rstate_d;

  logic [MEM_ADDR_WIDTH-1:0] raddr_q;
  logic [7:0] rbeats_left_q;  // beats remaining to *issue*, AXI beats-1 convention
  logic [ID_WIDTH-1:0] arid_q;
  logic read_pend_q;
  logic rlast_pend_q;

  assign arready = (rstate_q == R_IDLE);

  wire mem_r_en = !write_active && (rstate_q == R_BURST) && (!read_pend_q || rready);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rstate_q      <= R_IDLE;
      raddr_q       <= '0;
      rbeats_left_q <= '0;
      arid_q        <= '0;
      read_pend_q   <= 1'b0;
      rlast_pend_q  <= 1'b0;
    end else begin
      rstate_q <= rstate_d;

      if (rstate_q == R_IDLE && arvalid) begin
        raddr_q       <= araddr[MEM_ADDR_WIDTH+RowShift-1:RowShift];
        rbeats_left_q <= arlen;
        arid_q        <= arid;
      end else if (mem_r_en) begin
        raddr_q       <= raddr_q + 1'b1;
        rbeats_left_q <= rbeats_left_q - 1'b1;
      end

      if (mem_r_en) begin
        read_pend_q  <= 1'b1;
        rlast_pend_q <= (rbeats_left_q == 8'd0);
      end else if (rready) begin
        read_pend_q <= 1'b0;
      end
    end
  end

  always_comb begin
    rstate_d = rstate_q;
    case (rstate_q)
      R_IDLE:  if (arvalid) rstate_d = R_BURST;
      R_BURST: if (mem_r_en && rbeats_left_q == 8'd0) rstate_d = R_IDLE;
      default: rstate_d = R_IDLE;
    endcase
  end

  assign rvalid = read_pend_q;
  assign rdata  = mem_b_rdata;
  assign rresp  = 2'b00;
  assign rid    = arid_q;
  assign rlast  = read_pend_q && rlast_pend_q;

  // ---- Shared storage port mux (write priority) ----------------------
  always_comb begin
    if (write_active) begin
      mem_b_en    = 1'b1;
      mem_b_we    = 1'b1;
      mem_b_strb  = wstrb;
      mem_b_addr  = waddr_q;
      mem_b_wdata = wdata;
    end else begin
      mem_b_en    = mem_r_en;
      mem_b_we    = 1'b0;
      mem_b_strb  = '0;
      mem_b_addr  = raddr_q;
      mem_b_wdata = '0;
    end
  end

endmodule
