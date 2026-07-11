// Test harness wiring rtl/dma/tpe_dma.sv to a real rtl/sram/tpe_sram.sv
// scratchpad and the behavioral verif/models/axi4_ddr_model.sv, since none
// of those three are useful to verify in total isolation from each other
// -- the DMA only does something observable by actually moving data
// between them. Not RTL in its own right; this only exists for the
// testbench (mirrors how M4's tpe_top.sv will wire the real thing, but
// standalone here per the "verify each block before integration" plan).
//
// tpe_dma drives tpe_sram's port A (matches tpe_sram.sv's own comment:
// "Port A is intended for DMA fill/drain") and axi4_ddr_model's AXI slave
// ports. The testbench gets backdoor access to both memories: tpe_sram
// port B (renamed sram_tb_*) and axi4_ddr_model's bd_* port (renamed
// ddr_tb_*), both following the SyncPortAgent-compatible dp_ram
// convention so verif/cocotb_tb/env/SyncPortAgent drives them directly.
module dma_test_harness
  import tpe_pkg::*;
#(
    parameter int DDR_DEPTH = 4096
) (
    input logic clk,
    input logic rst_n,

    // DMA descriptor control
    input  logic [AXI_ADDR_WIDTH-1:0]  desc_mem_addr,
    input  logic [SRAM_ADDR_WIDTH-1:0] desc_sram_addr,
    input  logic [19:0]                desc_len,
    input  logic                       desc_dir,
    input  logic                       start,
    output logic                       busy,
    output logic                       done,
    output logic                       error,

    // SRAM backdoor test port (tpe_sram port B)
    input  logic                        sram_tb_en,
    input  logic                        sram_tb_we,
    input  logic [SRAM_STRB_WIDTH-1:0]  sram_tb_strb,
    input  logic [SRAM_ADDR_WIDTH-1:0]  sram_tb_addr,
    input  logic [SRAM_DATA_WIDTH-1:0]  sram_tb_wdata,
    output logic [SRAM_DATA_WIDTH-1:0]  sram_tb_rdata,

    // DDR backdoor test port (axi4_ddr_model bd_*)
    input  logic                        ddr_tb_en,
    input  logic                        ddr_tb_we,
    input  logic [SRAM_STRB_WIDTH-1:0]  ddr_tb_strb,
    input  logic [$clog2(DDR_DEPTH)-1:0] ddr_tb_addr,
    input  logic [SRAM_DATA_WIDTH-1:0]  ddr_tb_wdata,
    output logic [SRAM_DATA_WIDTH-1:0]  ddr_tb_rdata
);

  // DMA <-> SRAM (tpe_sram port A)
  logic                       dma_sram_en;
  logic                       dma_sram_we;
  logic [SRAM_STRB_WIDTH-1:0] dma_sram_strb;
  logic [SRAM_ADDR_WIDTH-1:0] dma_sram_addr;
  logic [SRAM_DATA_WIDTH-1:0] dma_sram_wdata;
  logic [SRAM_DATA_WIDTH-1:0] dma_sram_rdata;

  tpe_sram u_sram (
      .clk    (clk),
      .a_en   (dma_sram_en),
      .a_we   (dma_sram_we),
      .a_strb (dma_sram_strb),
      .a_addr (dma_sram_addr),
      .a_wdata(dma_sram_wdata),
      .a_rdata(dma_sram_rdata),
      .b_en   (sram_tb_en),
      .b_we   (sram_tb_we),
      .b_strb (sram_tb_strb),
      .b_addr (sram_tb_addr),
      .b_wdata(sram_tb_wdata),
      .b_rdata(sram_tb_rdata)
  );

  // DMA <-> DDR (AXI4)
  logic                        axi_awvalid, axi_awready;
  logic [AXI_ADDR_WIDTH-1:0]   axi_awaddr;
  logic [7:0]                  axi_awlen;
  logic [AXI_ID_WIDTH-1:0]     axi_awid;
  logic                        axi_wvalid, axi_wready, axi_wlast;
  logic [AXI_DATA_WIDTH-1:0]   axi_wdata;
  logic [AXI_STRB_WIDTH-1:0]   axi_wstrb;
  logic                        axi_bvalid, axi_bready;
  logic [1:0]                  axi_bresp;
  logic [AXI_ID_WIDTH-1:0]     axi_bid;
  logic                        axi_arvalid, axi_arready;
  logic [AXI_ADDR_WIDTH-1:0]   axi_araddr;
  logic [7:0]                  axi_arlen;
  logic [AXI_ID_WIDTH-1:0]     axi_arid;
  logic                        axi_rvalid, axi_rready, axi_rlast;
  logic [AXI_DATA_WIDTH-1:0]   axi_rdata;
  logic [1:0]                  axi_rresp;
  logic [AXI_ID_WIDTH-1:0]     axi_rid;

  tpe_dma u_dma (
      .clk           (clk),
      .rst_n         (rst_n),
      .desc_mem_addr (desc_mem_addr),
      .desc_sram_addr(desc_sram_addr),
      .desc_len      (desc_len),
      .desc_dir      (desc_dir),
      .start         (start),
      .busy          (busy),
      .done          (done),
      .error         (error),
      .m_awvalid(axi_awvalid), .m_awaddr(axi_awaddr), .m_awlen(axi_awlen), .m_awid(axi_awid), .m_awready(axi_awready),
      .m_wvalid(axi_wvalid), .m_wdata(axi_wdata), .m_wstrb(axi_wstrb), .m_wlast(axi_wlast), .m_wready(axi_wready),
      .m_bvalid(axi_bvalid), .m_bresp(axi_bresp), .m_bid(axi_bid), .m_bready(axi_bready),
      .m_arvalid(axi_arvalid), .m_araddr(axi_araddr), .m_arlen(axi_arlen), .m_arid(axi_arid), .m_arready(axi_arready),
      .m_rvalid(axi_rvalid), .m_rdata(axi_rdata), .m_rresp(axi_rresp), .m_rlast(axi_rlast), .m_rid(axi_rid), .m_rready(axi_rready),
      .sram_en   (dma_sram_en),
      .sram_we   (dma_sram_we),
      .sram_strb (dma_sram_strb),
      .sram_addr (dma_sram_addr),
      .sram_wdata(dma_sram_wdata),
      .sram_rdata(dma_sram_rdata)
  );

  axi4_ddr_model #(
      .ADDR_WIDTH(AXI_ADDR_WIDTH),
      .DATA_WIDTH(AXI_DATA_WIDTH),
      .DEPTH     (DDR_DEPTH),
      .ID_WIDTH  (AXI_ID_WIDTH)
  ) u_ddr (
      .clk    (clk),
      .rst_n  (rst_n),
      .awvalid(axi_awvalid), .awaddr(axi_awaddr), .awlen(axi_awlen), .awid(axi_awid), .awready(axi_awready),
      .wvalid(axi_wvalid), .wdata(axi_wdata), .wstrb(axi_wstrb), .wlast(axi_wlast), .wready(axi_wready),
      .bvalid(axi_bvalid), .bresp(axi_bresp), .bid(axi_bid), .bready(axi_bready),
      .arvalid(axi_arvalid), .araddr(axi_araddr), .arlen(axi_arlen), .arid(axi_arid), .arready(axi_arready),
      .rvalid(axi_rvalid), .rdata(axi_rdata), .rresp(axi_rresp), .rlast(axi_rlast), .rid(axi_rid), .rready(axi_rready),
      .bd_en   (ddr_tb_en),
      .bd_we   (ddr_tb_we),
      .bd_strb (ddr_tb_strb),
      .bd_addr (ddr_tb_addr),
      .bd_wdata(ddr_tb_wdata),
      .bd_rdata(ddr_tb_rdata)
  );

endmodule
