// RTL-side FSM + functional coverage for
// rtl/matrix_engine/matrix_engine_ctrl.sv, bound in by testbenches (see
// docs/verification/coverage_plan.md section 1). FSM state/arc coverage is
// the explicit "FSM coverage" verification requirement -- state_q's 3-bit
// enum encoding is covered directly rather than reimplemented in Python.
module matrix_engine_ctrl_cov #(
    parameter int DIM_WIDTH = 9
) (
    input logic clk,
    input logic rst_n,
    input logic [2:0] state_q,
    input logic [DIM_WIDTH-1:0] dim_m,
    input logic [DIM_WIDTH-1:0] dim_k,
    input logic [DIM_WIDTH-1:0] dim_n,
    input logic start,
    input logic overflow_sticky
);

  logic [2:0] prev_state_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) prev_state_q <= 3'd0;
    else prev_state_q <= state_q;
  end

  covergroup cg_fsm @(posedge clk);
    option.per_instance = 1;
    cp_state: coverpoint state_q {
      bins idle         = {0};
      bins load_weights = {1};
      bins compute      = {2};
      bins drain        = {3};
      bins done         = {4};
    }
    cp_arc: coverpoint {prev_state_q, state_q} {
      bins idle_to_load    = {{3'd0, 3'd1}};
      bins load_to_compute = {{3'd1, 3'd2}};
      bins compute_to_drain= {{3'd2, 3'd3}};
      bins drain_to_done   = {{3'd3, 3'd4}};
      bins done_to_idle    = {{3'd4, 3'd0}};
      bins other           = default;
    }
  endgroup

  // Local alias: covergroups have a built-in start() control method, which
  // collides with a bare `start` signal reference in the sensitivity list.
  wire start_ev = start;

  covergroup cg_dims @(posedge clk iff start_ev);
    option.per_instance = 1;
    cp_dim_k: coverpoint dim_k {
      bins one     = {1};
      bins mid     = {[2:14]};
      bins max_val = {15, 16};
    }
    cp_dim_n: coverpoint dim_n {
      bins one     = {1};
      bins mid     = {[2:14]};
      bins max_val = {15, 16};
    }
    cp_dim_m: coverpoint dim_m {
      bins narrow = {[1:4]};
      bins wide   = {[5:$]};
    }
  endgroup

  covergroup cg_overflow @(posedge clk);
    option.per_instance = 1;
    cp_overflow_sticky: coverpoint overflow_sticky;
  endgroup

  cg_fsm cg_fsm_inst = new();
  cg_dims cg_dims_inst = new();
  cg_overflow cg_overflow_inst = new();

endmodule

bind matrix_engine_ctrl matrix_engine_ctrl_cov #(
    .DIM_WIDTH(DIM_WIDTH)
) u_matrix_engine_ctrl_cov (
    .clk             (clk),
    .rst_n           (rst_n),
    .state_q         (state_q),
    .dim_m           (dim_m),
    .dim_k           (dim_k),
    .dim_n           (dim_n),
    .start           (start),
    .overflow_sticky (overflow_sticky)
);
