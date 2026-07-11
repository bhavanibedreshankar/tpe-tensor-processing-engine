// Protocol + counter-sanity checks for rtl/pmu/tpe_pmu.sv, bound in by
// testbenches (see verif/sva/sram_sva.sv for the convention).
module tpe_pmu_sva (
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
    input logic ctrl_reset_counters_q,
    input logic [31:0] cycle_count_q
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

  // The free-running cycle counter never decreases except when
  // RESET_COUNTERS is held (or on rollover, unreachable at 32 bits within
  // any V1 test's runtime).
  a_cycle_count_monotonic :
  assert property (@(posedge clk) disable iff (!rst_n)
      !ctrl_reset_counters_q |-> (cycle_count_q >= $past(cycle_count_q)));

endmodule

bind tpe_pmu tpe_pmu_sva u_tpe_pmu_sva (
    .clk(clk), .rst_n(rst_n),
    .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bvalid(s_bvalid), .s_bready(s_bready),
    .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rvalid(s_rvalid), .s_rready(s_rready),
    .ctrl_reset_counters_q(ctrl_reset_counters_q),
    .cycle_count_q(cycle_count_q)
);
