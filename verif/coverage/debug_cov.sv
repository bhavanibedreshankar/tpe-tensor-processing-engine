// Functional coverage for rtl/debug/tpe_debug.sv -- trace-buffer fill
// state and which opcode/status combinations actually got traced
// (docs/verification/coverage_plan.md section 1).
module tpe_debug_cov (
    input logic clk,
    input logic rst_n,
    input logic ctrl_trace_enable_q,
    input logic trace_wr_en,
    input logic trace_empty,
    input logic trace_full,
    input logic [3:0] sched_done_opcode,
    input logic [2:0] sched_done_status
);

  covergroup cg_trace @(posedge clk);
    option.per_instance = 1;
    cp_enable: coverpoint ctrl_trace_enable_q;
    cp_fill: coverpoint {trace_empty, trace_full} {
      bins mid_empty_full = {2'b00};
      bins empty          = {2'b01};
      bins full            = {2'b10};
    }
  endgroup

  covergroup cg_push @(posedge clk iff trace_wr_en);
    option.per_instance = 1;
    cp_opcode: coverpoint sched_done_opcode {
      bins nop         = {4'h0};
      bins load_weight = {4'h1};
      bins load_act    = {4'h2};
      bins matmul      = {4'h3};
      bins store       = {4'h4};
      bins barrier     = {4'h5};
      bins irq_test    = {4'hE};
      bins bad_opcode  = default;
    }
    cp_status: coverpoint sched_done_status {
      bins ok         = {0};
      bins bad_opcode = {1};
      bins bad_dim    = {2};
      bins mem_error  = {4};
      bins overflow   = {5};
    }
  endgroup

  cg_trace cg_trace_inst = new();
  cg_push cg_push_inst = new();

endmodule

bind tpe_debug tpe_debug_cov u_tpe_debug_cov (
    .clk(clk), .rst_n(rst_n),
    .ctrl_trace_enable_q(ctrl_trace_enable_q),
    .trace_wr_en(trace_wr_en),
    .trace_empty(trace_empty),
    .trace_full(trace_full),
    .sched_done_opcode(sched_done_opcode),
    .sched_done_status(sched_done_status)
);
