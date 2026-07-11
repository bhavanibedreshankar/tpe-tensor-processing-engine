// RTL-side FSM + functional coverage for rtl/scheduler/tpe_scheduler.sv
// (the command-dispatch FSM and opcode mix), bound in by testbenches (see
// docs/verification/coverage_plan.md section 1).
module tpe_scheduler_cov (
    input logic clk,
    input logic rst_n,
    input logic [2:0] state_q,
    input logic [3:0] cmd_q_opcode,
    input logic sched_done_valid,
    input logic [2:0] status_q
);

  logic [2:0] prev_state_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) prev_state_q <= 3'd0;
    else prev_state_q <= state_q;
  end

  covergroup cg_fsm @(posedge clk);
    option.per_instance = 1;
    cp_state: coverpoint state_q {
      bins idle          = {0};
      bins pop           = {1};
      bins decode        = {2};
      bins dispatch_dma  = {3};
      bins wait_dma      = {4};
      bins dispatch_me   = {5};
      bins wait_me       = {6};
      bins complete      = {7};
    }
    cp_arc: coverpoint {prev_state_q, state_q} {
      bins decode_to_dma = {{3'd2, 3'd3}};
      bins decode_to_me  = {{3'd2, 3'd5}};
      bins decode_to_complete_direct = {{3'd2, 3'd7}};  // NOP/BARRIER/IRQ_TEST/bad-opcode
      bins other = default;
    }
  endgroup

  covergroup cg_opcode @(posedge clk iff sched_done_valid);
    option.per_instance = 1;
    cp_opcode: coverpoint cmd_q_opcode {
      bins nop         = {4'h0};
      bins load_weight = {4'h1};
      bins load_act    = {4'h2};
      bins matmul      = {4'h3};
      bins store       = {4'h4};
      bins barrier     = {4'h5};
      bins irq_test    = {4'hE};
      bins bad_opcode  = default;
    }
    cp_status: coverpoint status_q {
      bins ok        = {0};
      bins bad_opcode = {1};
      bins bad_dim    = {2};
      bins mem_error  = {4};
      bins overflow   = {5};
    }
    cx_opcode_status: cross cp_opcode, cp_status;
  endgroup

  cg_fsm cg_fsm_inst = new();
  cg_opcode cg_opcode_inst = new();

endmodule

bind tpe_scheduler tpe_scheduler_cov u_tpe_scheduler_cov (
    .clk         (clk),
    .rst_n       (rst_n),
    .state_q     (state_q),
    .cmd_q_opcode(cmd_q.opcode),
    .sched_done_valid(sched_done_valid),
    .status_q    (status_q)
);
