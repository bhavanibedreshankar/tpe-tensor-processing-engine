// Protocol checks for rtl/dma/tpe_dma.sv and verif/models/axi4_ddr_model.sv,
// bound in by testbenches (see verif/sva/sram_sva.sv for the convention).
// Focus: standard AXI4 VALID-stability (once asserted without READY, VALID
// must not drop) on both the master (tpe_dma) and slave (axi4_ddr_model)
// sides, plus no-X checks on data phases.
module tpe_dma_sva (
    input logic clk,
    input logic rst_n,
    input logic m_arvalid,
    input logic m_arready,
    input logic m_awvalid,
    input logic m_awready,
    input logic m_wvalid,
    input logic m_wready,
    input logic busy,
    input logic done,
    input logic error
);

  a_arvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n)
      (m_arvalid && !m_arready) |=> m_arvalid);

  a_awvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n)
      (m_awvalid && !m_awready) |=> m_awvalid);

  a_wvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n)
      (m_wvalid && !m_wready) |=> m_wvalid);

  a_done_and_error_mutually_exclusive :
  assert property (@(posedge clk) disable iff (!rst_n) !(done && error));

  a_done_implies_was_busy :
  assert property (@(posedge clk) disable iff (!rst_n) done |-> $past(busy));

endmodule

bind tpe_dma tpe_dma_sva u_tpe_dma_sva (
    .clk      (clk),
    .rst_n    (rst_n),
    .m_arvalid(m_arvalid),
    .m_arready(m_arready),
    .m_awvalid(m_awvalid),
    .m_awready(m_awready),
    .m_wvalid (m_wvalid),
    .m_wready (m_wready),
    .busy     (busy),
    .done     (done),
    .error    (error)
);

module axi4_ddr_model_sva #(
    parameter int DATA_WIDTH = 128
) (
    input logic clk,
    input logic rst_n,
    input logic rvalid,
    input logic rready,
    input logic signed [DATA_WIDTH-1:0] rdata,
    input logic bvalid,
    input logic bready
);

  a_rvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (rvalid && !rready) |=> rvalid);

  a_bvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (bvalid && !bready) |=> bvalid);

  a_rdata_known_when_valid :
  assert property (@(posedge clk) disable iff (!rst_n) rvalid |-> !$isunknown(rdata));

endmodule

bind axi4_ddr_model axi4_ddr_model_sva #(
    .DATA_WIDTH(DATA_WIDTH)
) u_axi4_ddr_model_sva (
    .clk   (clk),
    .rst_n (rst_n),
    .rvalid(rvalid),
    .rready(rready),
    .rdata (rdata),
    .bvalid(bvalid),
    .bready(bready)
);
