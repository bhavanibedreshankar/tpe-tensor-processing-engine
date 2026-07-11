// Test harness wiring rtl/top/tpe_top.sv's AXI4 master (DDR) port to the
// behavioral verif/models/axi4_ddr_model.sv, exposing tpe_top's AXI4-Lite
// slave (host MMIO), irq, and the DDR model's backdoor test port. Not RTL
// in its own right -- mirrors verif/cocotb_tb/dma/dma_test_harness.sv's
// role for the DMA-alone testbench, one level up.
module top_test_harness
  import tpe_pkg::*;
#(
    parameter int DDR_DEPTH = 4096
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

    // DDR backdoor test port (axi4_ddr_model bd_*)
    input  logic                         ddr_tb_en,
    input  logic                         ddr_tb_we,
    input  logic [   SRAM_STRB_WIDTH-1:0] ddr_tb_strb,
    input  logic [$clog2(DDR_DEPTH)-1:0] ddr_tb_addr,
    input  logic [   SRAM_DATA_WIDTH-1:0] ddr_tb_wdata,
    output logic [   SRAM_DATA_WIDTH-1:0] ddr_tb_rdata
);

  logic                      axi_awvalid, axi_awready;
  logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
  logic [               7:0] axi_awlen;
  logic [ AXI_ID_WIDTH-1:0]  axi_awid;
  logic                      axi_wvalid, axi_wready, axi_wlast;
  logic [AXI_DATA_WIDTH-1:0] axi_wdata;
  logic [AXI_STRB_WIDTH-1:0] axi_wstrb;
  logic                      axi_bvalid, axi_bready;
  logic [               1:0] axi_bresp;
  logic [ AXI_ID_WIDTH-1:0]  axi_bid;
  logic                      axi_arvalid, axi_arready;
  logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
  logic [               7:0] axi_arlen;
  logic [ AXI_ID_WIDTH-1:0]  axi_arid;
  logic                      axi_rvalid, axi_rready, axi_rlast;
  logic [AXI_DATA_WIDTH-1:0] axi_rdata;
  logic [               1:0] axi_rresp;
  logic [ AXI_ID_WIDTH-1:0]  axi_rid;

  tpe_top u_top (
      .clk  (clk),
      .rst_n(rst_n),
      .s_awvalid(s_awvalid), .s_awaddr(s_awaddr), .s_awready(s_awready),
      .s_wvalid(s_wvalid), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wready(s_wready),
      .s_bvalid(s_bvalid), .s_bresp(s_bresp), .s_bready(s_bready),
      .s_arvalid(s_arvalid), .s_araddr(s_araddr), .s_arready(s_arready),
      .s_rvalid(s_rvalid), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rready(s_rready),
      .irq(irq),
      .m_awvalid(axi_awvalid), .m_awaddr(axi_awaddr), .m_awlen(axi_awlen), .m_awid(axi_awid), .m_awready(axi_awready),
      .m_wvalid(axi_wvalid), .m_wdata(axi_wdata), .m_wstrb(axi_wstrb), .m_wlast(axi_wlast), .m_wready(axi_wready),
      .m_bvalid(axi_bvalid), .m_bresp(axi_bresp), .m_bid(axi_bid), .m_bready(axi_bready),
      .m_arvalid(axi_arvalid), .m_araddr(axi_araddr), .m_arlen(axi_arlen), .m_arid(axi_arid), .m_arready(axi_arready),
      .m_rvalid(axi_rvalid), .m_rdata(axi_rdata), .m_rresp(axi_rresp), .m_rlast(axi_rlast), .m_rid(axi_rid), .m_rready(axi_rready)
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
