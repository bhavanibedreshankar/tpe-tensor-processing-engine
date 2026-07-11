// Functional coverage for rtl/pmu/tpe_pmu.sv -- did a regression exercise
// each event class the counter bank is meant to track, and the
// enable/reset control bits themselves (docs/verification/coverage_plan.md
// section 1).
module tpe_pmu_cov (
    input logic clk,
    input logic rst_n,
    input logic ctrl_enable_q,
    input logic ctrl_reset_counters_q,
    input logic mac_active,
    input logic dma_wait,
    input logic sched_stall,
    input logic sched_idle
);

  covergroup cg_ctrl @(posedge clk);
    option.per_instance = 1;
    cp_enable: coverpoint ctrl_enable_q;
    cp_reset:  coverpoint ctrl_reset_counters_q;
  endgroup

  covergroup cg_events @(posedge clk iff (rst_n && ctrl_enable_q && !ctrl_reset_counters_q));
    option.per_instance = 1;
    cp_mac_active: coverpoint mac_active;
    cp_dma_wait:   coverpoint dma_wait;
    cp_sched_stall: coverpoint sched_stall;
    cp_sched_idle:  coverpoint sched_idle;
  endgroup

  cg_ctrl cg_ctrl_inst = new();
  cg_events cg_events_inst = new();

endmodule

bind tpe_pmu tpe_pmu_cov u_tpe_pmu_cov (
    .clk(clk), .rst_n(rst_n),
    .ctrl_enable_q(ctrl_enable_q),
    .ctrl_reset_counters_q(ctrl_reset_counters_q),
    .mac_active(mac_active),
    .dma_wait(dma_wait),
    .sched_stall(sched_stall),
    .sched_idle(sched_idle)
);
