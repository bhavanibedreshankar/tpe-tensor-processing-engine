// Protocol checks for rtl/command_processor/tpe_cmd_proc.sv and
// rtl/scheduler/tpe_scheduler.sv, bound in by testbenches (see
// verif/sva/sram_sva.sv for the convention).
module tpe_cmd_proc_sva (
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
    input logic irq,
    input logic [1:0] irq_status_q,
    input logic [1:0] irq_enable_q
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

  a_irq_matches_status_and_enable :
  assert property (@(posedge clk) disable iff (!rst_n) irq == |(irq_status_q & irq_enable_q));

endmodule

bind tpe_cmd_proc tpe_cmd_proc_sva u_tpe_cmd_proc_sva (
    .clk(clk), .rst_n(rst_n),
    .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bvalid(s_bvalid), .s_bready(s_bready),
    .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rvalid(s_rvalid), .s_rready(s_rready),
    .irq(irq),
    .irq_status_q(irq_status_q),
    .irq_enable_q(irq_enable_q)
);

module tpe_scheduler_sva (
    input logic clk,
    input logic rst_n,
    input logic cmd_fifo_empty,
    input logic cmd_fifo_rd_en,
    input logic sched_done_valid,
    input logic sched_busy
);

  a_no_pop_when_empty :
  assert property (@(posedge clk) disable iff (!rst_n) cmd_fifo_rd_en |-> !cmd_fifo_empty)
  else $error("tpe_scheduler: popped the command FIFO while empty");

  a_done_implies_was_busy :
  assert property (@(posedge clk) disable iff (!rst_n) sched_done_valid |-> $past(sched_busy));

endmodule

bind tpe_scheduler tpe_scheduler_sva u_tpe_scheduler_sva (
    .clk(clk), .rst_n(rst_n),
    .cmd_fifo_empty(cmd_fifo_empty),
    .cmd_fifo_rd_en(cmd_fifo_rd_en),
    .sched_done_valid(sched_done_valid),
    .sched_busy(sched_busy)
);
