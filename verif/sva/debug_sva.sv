// Protocol + trace-FIFO checks for rtl/debug/tpe_debug.sv, bound in by
// testbenches (see verif/sva/sram_sva.sv for the convention).
module tpe_debug_sva (
    input logic clk,
    input logic rst_n,
    input logic s_awvalid,
    input logic s_awready,
    input logic s_wvalid,
    input logic s_wready,
    input logic s_bvalid,
    input logic s_bready,
    input logic s_arvalid,
    input logic s_arready,
    input logic s_rvalid,
    input logic s_rready,
    input logic trace_rd_en,
    input logic trace_empty
);

  a_awvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (s_awvalid && !s_awready) |=> s_awvalid);
  a_wvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (s_wvalid && !s_wready) |=> s_wvalid);
  a_bvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (s_bvalid && !s_bready) |=> s_bvalid);
  a_arvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (s_arvalid && !s_arready) |=> s_arvalid);
  a_rvalid_stable :
  assert property (@(posedge clk) disable iff (!rst_n) (s_rvalid && !s_rready) |=> s_rvalid);

  a_no_pop_when_empty :
  assert property (@(posedge clk) disable iff (!rst_n) trace_rd_en |-> !trace_empty)
  else $error("tpe_debug: popped the trace FIFO while empty");

endmodule

bind tpe_debug tpe_debug_sva u_tpe_debug_sva (
    .clk(clk), .rst_n(rst_n),
    .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bvalid(s_bvalid), .s_bready(s_bready),
    .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rvalid(s_rvalid), .s_rready(s_rready),
    .trace_rd_en(trace_rd_en),
    .trace_empty(trace_empty)
);
