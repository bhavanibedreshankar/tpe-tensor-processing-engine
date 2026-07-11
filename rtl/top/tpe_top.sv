// TPE top level: Command Processor -> Scheduler -> {DMA Engine, Matrix
// Compute Engine}, per docs/architecture/tpe_architecture_spec.md. V1
// scope: matmul only (load weight, load activation, matmul, store), no
// activation unit (V2), no double buffering / overlap (V2's "improved
// scheduler" -- see tpe_scheduler.sv's header comment).
//
// V1 architecture note: matrix_engine's four internal buffers
// (weight/act/seed/out, see matrix_engine.sv) serve directly as the
// addressable "Local SRAM" region for V1's matmul-only command flow --
// there is no separate shared rtl/sram/tpe_sram.sv instance in this V1 top
// level. tpe_sram remains a fully verified, standalone, reusable block
// (M1) that a future multi-engine/multi-channel scheduler (V2+) would wire
// in as an actual shared scratchpad between multiple consumers; V1's
// single DMA channel + single compute engine don't need that extra layer.
// The DMA's single SRAM-side port is routed to whichever of the four
// buffers the in-flight command targets (g_sram_router below), selected by
// tpe_scheduler's router_sel. Loading (LOAD_WEIGHT/LOAD_ACT) is a direct
// width match (both AXI and weight_buf/act_buf rows are AXI_DATA_WIDTH=128b
// at the default ROWS=COLS=16 array size); storing reads through
// g_obuf_chunk_adapter below since out_buf's row (COLS*ACCUM_WIDTH=512b) is
// 4x wider than one AXI beat.
module tpe_top
  import tpe_pkg::*;
#(
    parameter int ROWS           = MAC_ARRAY_ROWS,
    parameter int COLS           = MAC_ARRAY_COLS,
    parameter int ME_MAX_M       = MAX_TILE_DIM,
    parameter int CMD_FIFO_DEPTH = 4,
    localparam int ObufChunksPerRow = (COLS * ACCUM_WIDTH) / AXI_DATA_WIDTH,
    localparam int ObufChunkSelWidth = $clog2(ObufChunksPerRow),
    localparam int MeMAddrWidth = $clog2(ME_MAX_M),
    localparam int WbufAddrWidth = $clog2(ROWS)
) (
    input logic clk,
    input logic rst_n,

    // Host AXI4-Lite MMIO
    input  logic                       s_awvalid,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_awaddr,
    output logic                       s_awready,
    input  logic                       s_wvalid,
    input  logic [AXIL_DATA_WIDTH-1:0] s_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0] s_wstrb,
    output logic                       s_wready,
    output logic                       s_bvalid,
    output logic [               1:0] s_bresp,
    input  logic                       s_bready,
    input  logic                       s_arvalid,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_araddr,
    output logic                       s_arready,
    output logic                       s_rvalid,
    output logic [AXIL_DATA_WIDTH-1:0] s_rdata,
    output logic [               1:0] s_rresp,
    input  logic                       s_rready,

    output logic irq,

    // DDR AXI4 master (external memory)
    output logic                      m_awvalid,
    output logic [AXI_ADDR_WIDTH-1:0] m_awaddr,
    output logic [               7:0] m_awlen,
    output logic [ AXI_ID_WIDTH-1:0]  m_awid,
    input  logic                      m_awready,
    output logic                      m_wvalid,
    output logic [AXI_DATA_WIDTH-1:0] m_wdata,
    output logic [AXI_STRB_WIDTH-1:0] m_wstrb,
    output logic                      m_wlast,
    input  logic                      m_wready,
    input  logic                      m_bvalid,
    input  logic [               1:0] m_bresp,
    input  logic [ AXI_ID_WIDTH-1:0]  m_bid,
    output logic                      m_bready,
    output logic                      m_arvalid,
    output logic [AXI_ADDR_WIDTH-1:0] m_araddr,
    output logic [               7:0] m_arlen,
    output logic [ AXI_ID_WIDTH-1:0]  m_arid,
    input  logic                      m_arready,
    input  logic                      m_rvalid,
    input  logic [AXI_DATA_WIDTH-1:0] m_rdata,
    input  logic [               1:0] m_rresp,
    input  logic                      m_rlast,
    input  logic [ AXI_ID_WIDTH-1:0]  m_rid,
    output logic                      m_rready
);

  // ---- Command Processor <-> Scheduler -----------------------------------
  logic         cmd_fifo_empty, cmd_fifo_rd_en, cmd_fifo_rd_valid;
  tpe_command_t cmd_fifo_rd_data;
  logic         sched_done_valid, sched_busy;
  logic [11:0]  sched_done_tag;
  cmd_status_e  sched_done_status;

  tpe_cmd_proc #(
      .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH)
  ) u_cmd_proc (
      .clk  (clk),
      .rst_n(rst_n),
      .s_awvalid(s_awvalid), .s_awaddr(s_awaddr), .s_awready(s_awready),
      .s_wvalid(s_wvalid), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wready(s_wready),
      .s_bvalid(s_bvalid), .s_bresp(s_bresp), .s_bready(s_bready),
      .s_arvalid(s_arvalid), .s_araddr(s_araddr), .s_arready(s_arready),
      .s_rvalid(s_rvalid), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rready(s_rready),
      .irq(irq),
      .cmd_fifo_empty(cmd_fifo_empty),
      .cmd_fifo_rd_en(cmd_fifo_rd_en),
      .cmd_fifo_rd_valid(cmd_fifo_rd_valid),
      .cmd_fifo_rd_data(cmd_fifo_rd_data),
      .sched_done_valid(sched_done_valid),
      .sched_done_tag(sched_done_tag),
      .sched_done_status(sched_done_status),
      .sched_busy(sched_busy)
  );

  // ---- Scheduler <-> DMA / Matrix Engine ----------------------------------
  logic [AXI_ADDR_WIDTH-1:0]  dma_desc_mem_addr;
  logic [SRAM_ADDR_WIDTH-1:0] dma_desc_sram_addr;
  logic [19:0]                dma_desc_len;
  logic                       dma_desc_dir;
  logic                       dma_start, dma_busy, dma_done, dma_error;

  logic                      me_start, me_busy, me_done, me_overflow_sticky;
  logic [TILE_DIM_WIDTH-1:0] me_dim_m, me_dim_k, me_dim_n;

  logic [1:0] router_sel;

  tpe_scheduler #(
      .ROWS(ROWS),
      .COLS(COLS)
  ) u_scheduler (
      .clk  (clk),
      .rst_n(rst_n),
      .cmd_fifo_empty(cmd_fifo_empty),
      .cmd_fifo_rd_en(cmd_fifo_rd_en),
      .cmd_fifo_rd_valid(cmd_fifo_rd_valid),
      .cmd_fifo_rd_data(cmd_fifo_rd_data),
      .sched_done_valid(sched_done_valid),
      .sched_done_tag(sched_done_tag),
      .sched_done_status(sched_done_status),
      .sched_busy(sched_busy),
      .dma_desc_mem_addr(dma_desc_mem_addr),
      .dma_desc_sram_addr(dma_desc_sram_addr),
      .dma_desc_len(dma_desc_len),
      .dma_desc_dir(dma_desc_dir),
      .dma_start(dma_start),
      .dma_busy(dma_busy),
      .dma_done(dma_done),
      .dma_error(dma_error),
      .me_start(me_start),
      .me_dim_m(me_dim_m),
      .me_dim_k(me_dim_k),
      .me_dim_n(me_dim_n),
      .me_busy(me_busy),
      .me_done(me_done),
      .me_overflow_sticky(me_overflow_sticky),
      .router_sel(router_sel)
  );

  // ---- DMA <-> SRAM router (DMA's single port) ----------------------------
  logic                        dma_sram_en, dma_sram_we;
  logic [SRAM_STRB_WIDTH-1:0]  dma_sram_strb;
  logic [SRAM_ADDR_WIDTH-1:0]  dma_sram_addr;
  logic [SRAM_DATA_WIDTH-1:0]  dma_sram_wdata;
  logic [SRAM_DATA_WIDTH-1:0]  dma_sram_rdata;

  tpe_dma u_dma (
      .clk  (clk),
      .rst_n(rst_n),
      .desc_mem_addr (dma_desc_mem_addr),
      .desc_sram_addr(dma_desc_sram_addr),
      .desc_len      (dma_desc_len),
      .desc_dir      (dma_desc_dir),
      .start(dma_start), .busy(dma_busy), .done(dma_done), .error(dma_error),
      .m_awvalid(m_awvalid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awid(m_awid), .m_awready(m_awready),
      .m_wvalid(m_wvalid), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wready(m_wready),
      .m_bvalid(m_bvalid), .m_bresp(m_bresp), .m_bid(m_bid), .m_bready(m_bready),
      .m_arvalid(m_arvalid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arid(m_arid), .m_arready(m_arready),
      .m_rvalid(m_rvalid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rid(m_rid), .m_rready(m_rready),
      .sram_en   (dma_sram_en),
      .sram_we   (dma_sram_we),
      .sram_strb (dma_sram_strb),
      .sram_addr (dma_sram_addr),
      .sram_wdata(dma_sram_wdata),
      .sram_rdata(dma_sram_rdata)
  );

  // ---- Matrix Engine -------------------------------------------------------
  logic wbuf_a_en, wbuf_a_we;
  logic [COLS-1:0] wbuf_a_strb;
  logic [TILE_DIM_WIDTH-1:0] wbuf_a_addr;
  logic [COLS*OPERAND_WIDTH-1:0] wbuf_a_wdata, wbuf_a_rdata;

  logic abuf_a_en, abuf_a_we;
  logic [ROWS-1:0] abuf_a_strb;
  logic [MeMAddrWidth-1:0] abuf_a_addr;
  logic [ROWS*OPERAND_WIDTH-1:0] abuf_a_wdata, abuf_a_rdata;

  logic sbuf_a_en, sbuf_a_we;
  logic [COLS*4-1:0] sbuf_a_strb;
  logic [MeMAddrWidth-1:0] sbuf_a_addr;
  logic [COLS*ACCUM_WIDTH-1:0] sbuf_a_wdata, sbuf_a_rdata;

  logic obuf_a_en, obuf_a_we;
  logic [COLS*4-1:0] obuf_a_strb;
  logic [MeMAddrWidth-1:0] obuf_a_addr;
  logic [COLS*ACCUM_WIDTH-1:0] obuf_a_wdata, obuf_a_rdata;

  matrix_engine #(
      .ROWS (ROWS),
      .COLS (COLS),
      .MAX_M(ME_MAX_M)
  ) u_matrix_engine (
      .clk  (clk),
      .rst_n(rst_n),
      .start(me_start), .dim_m(me_dim_m), .dim_k(me_dim_k), .dim_n(me_dim_n),
      .busy (me_busy), .done(me_done), .overflow_sticky(me_overflow_sticky),
      .wbuf_a_en(wbuf_a_en), .wbuf_a_we(wbuf_a_we), .wbuf_a_strb(wbuf_a_strb),
      .wbuf_a_addr(wbuf_a_addr), .wbuf_a_wdata(wbuf_a_wdata), .wbuf_a_rdata(wbuf_a_rdata),
      .abuf_a_en(abuf_a_en), .abuf_a_we(abuf_a_we), .abuf_a_strb(abuf_a_strb),
      .abuf_a_addr(abuf_a_addr), .abuf_a_wdata(abuf_a_wdata), .abuf_a_rdata(abuf_a_rdata),
      .sbuf_a_en(sbuf_a_en), .sbuf_a_we(sbuf_a_we), .sbuf_a_strb(sbuf_a_strb),
      .sbuf_a_addr(sbuf_a_addr), .sbuf_a_wdata(sbuf_a_wdata), .sbuf_a_rdata(sbuf_a_rdata),
      .obuf_a_en(obuf_a_en), .obuf_a_we(obuf_a_we), .obuf_a_strb(obuf_a_strb),
      .obuf_a_addr(obuf_a_addr), .obuf_a_wdata(obuf_a_wdata), .obuf_a_rdata(obuf_a_rdata)
  );

  // seed_buf is never DMA-driven in V1 (no LOAD_SEED opcode) -- always idle,
  // matmul always runs with a fresh (zero) accumulator seed.
  assign sbuf_a_en    = 1'b0;
  assign sbuf_a_we    = 1'b0;
  assign sbuf_a_strb  = '0;
  assign sbuf_a_addr  = '0;
  assign sbuf_a_wdata = '0;

  localparam logic [1:0] RouterWeight = 2'd0;
  localparam logic [1:0] RouterAct = 2'd1;
  localparam logic [1:0] RouterOut = 2'd3;

  // Weight/activation: direct width match (both AXI_DATA_WIDTH and
  // wbuf/abuf row width are 128b at the default array size), simple mux.
  assign wbuf_a_en    = dma_sram_en && (router_sel == RouterWeight);
  assign wbuf_a_we    = dma_sram_we;
  assign wbuf_a_strb  = dma_sram_strb[COLS-1:0];
  assign wbuf_a_addr  = TILE_DIM_WIDTH'(dma_sram_addr[WbufAddrWidth-1:0]);
  assign wbuf_a_wdata = dma_sram_wdata[COLS*OPERAND_WIDTH-1:0];

  assign abuf_a_en    = dma_sram_en && (router_sel == RouterAct);
  assign abuf_a_we    = dma_sram_we;
  assign abuf_a_strb  = dma_sram_strb[ROWS-1:0];
  assign abuf_a_addr  = dma_sram_addr[MeMAddrWidth-1:0];
  assign abuf_a_wdata = dma_sram_wdata[ROWS*OPERAND_WIDTH-1:0];

  // Output: chunk-addressed read-only adapter (out_buf's row is
  // ObufChunksPerRow x wider than one AXI beat -- see this module's header
  // comment). dma_sram_addr from the scheduler is already chunk-scaled
  // (sram_addr * ObufChunksPerRow, see tpe_scheduler.sv).
  wire [ObufChunkSelWidth-1:0] obuf_chunk_sel = dma_sram_addr[ObufChunkSelWidth-1:0];
  wire [MeMAddrWidth-1:0] obuf_row_addr = dma_sram_addr[MeMAddrWidth+ObufChunkSelWidth-1:ObufChunkSelWidth];

  assign obuf_a_en    = dma_sram_en && (router_sel == RouterOut);
  assign obuf_a_we    = 1'b0;  // STORE only ever reads out_buf
  assign obuf_a_strb  = '0;
  assign obuf_a_addr  = obuf_row_addr;
  assign obuf_a_wdata = '0;

  logic [ObufChunkSelWidth-1:0] obuf_chunk_sel_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) obuf_chunk_sel_q <= '0;
    else if (obuf_a_en) obuf_chunk_sel_q <= obuf_chunk_sel;
  end

  // ---- SRAM read-data mux back to DMA -------------------------------------
  always_comb begin
    unique case (router_sel)
      RouterWeight: dma_sram_rdata = {{(SRAM_DATA_WIDTH - COLS * OPERAND_WIDTH) {1'b0}}, wbuf_a_rdata};
      RouterAct:    dma_sram_rdata = {{(SRAM_DATA_WIDTH - ROWS * OPERAND_WIDTH) {1'b0}}, abuf_a_rdata};
      RouterOut:    dma_sram_rdata = obuf_a_rdata[obuf_chunk_sel_q*AXI_DATA_WIDTH+:AXI_DATA_WIDTH];
      default:      dma_sram_rdata = '0;
    endcase
  end

endmodule
